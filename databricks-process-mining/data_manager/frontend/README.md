# Vue-Frontend des Data Managers: Regeln für das Prozess-Monitoring

Das Frontend (Vue 3) löst Statuswechsel aus, **entscheidet aber nie selbst**, welcher Schritt
erlaubt ist. Maßgeblich ist immer die Status-Maschine im Backend (`StateMachine`).

## Regeln

1. **Aktionen nur aus dem Backend:** Buttons und Menüs zeigen genau die Übergänge aus
   `GET …/transitions` (`StateMachine.allowed_next`). Keine Statuslisten oder Übergangsregeln im
   Frontend-Code.
2. **Jeder Statuswechsel über einen Endpoint**, der `StateMachine.transition()` aufruft. Kein
   generisches „Objekt speichern“, das den Status mitändert.
3. **Abgewiesene Versuche** liefern HTTP 409 mit verständlicher Meldung. Das Backend hat das
   `rejected`-Event bereits in einer eigenen Transaktion gespeichert. Die UI zeigt die Meldung
   an und lädt die erlaubten Aktionen neu.
4. **Kanal und Akteur setzt das Backend** aus Session bzw. Token (`channel="ui"`, `actor` =
   angemeldeter User), nicht aus Request-Daten.
5. **Trace-Kontext mitschicken** (`traceparent`, W3C/OpenTelemetry). Das Backend übernimmt die
   Trace-ID ins Event (`trace_id`); damit sind Events mit dem Application Monitoring verknüpfbar.
6. **Admin-Oberflächen** nutzen dieselben Endpoints mit `channel="admin_api"` und Pflichtfeld
   `reason`. Es gibt keine Abkürzung am Workflow vorbei.

## Bausteine

| Datei | Inhalt |
|---|---|
| `useWorkflow.ts` | Composable: erlaubte Übergänge laden, Statuswechsel auslösen, 409 behandeln, `traceparent` setzen |
| `WorkflowActions.vue` | Komponente: zeigt nur erlaubte Aktionen, Meldung bei Abweisung |

## Backend-Endpoints (Beispiel FastAPI)

```python
@router.get("/api/workflows/{process}/{case_id}/transitions")
def allowed(process: str, case_id: str, db=Depends(session)):
    return sm.allowed_next(process, None if case_id == "new" else case_id, db, channel="ui")

@router.post("/api/workflows/{process}/{case_id}/transitions")
def change(process: str, case_id: str, body: TransitionIn, user=Depends(current_user), db=Depends(session)):
    try:
        with db.begin():
            ev = sm.transition(process, case_id, body.to, actor=user.id, channel="ui", conn=db,
                               reason=body.reason, trace_id=current_trace_id())
        return {"event_id": ev.event_id, "activity": ev.activity}
    except TransitionRejected as e:                 # Event liegt bereits in process_event (reject_sink)
        raise HTTPException(409, {"detail": str(e), "event_id": e.event.event_id})
```

Hinweis: Die Dateien sind Bausteine und wurden **nicht** in einem Vue-Build getestet. Pfade,
Auth und das HTTP-Client-Setup sind an euer Projekt anzupassen.
