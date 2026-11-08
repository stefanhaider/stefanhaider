// Vue 3 Composable: Statuswechsel im Data Manager – die UI entscheidet NIE selbst, was erlaubt ist.
//
// API-Vertrag (Backend, z. B. FastAPI) – siehe README.md in diesem Ordner:
//   GET  /api/workflows/{process}/{caseId}/transitions   -> [{ to, note }]   (StateMachine.allowed_next)
//   POST /api/workflows/{process}/{caseId}/transitions   { to, reason? }
//        200 -> { event_id, activity }   409 -> { detail, event_id }  (TransitionRejected, Event ist protokolliert)
//
// Der Kanal ("ui") und der Akteur setzt das Backend aus Session/Token – nicht der Client.
// traceparent (W3C/OpenTelemetry) wird mitgeschickt, damit Event und Application Monitoring verknüpfbar sind.
import { ref, type Ref } from "vue";

export interface AllowedTransition { to: string; note?: string }

function traceparent(): string {
  const hex = (n: number) => Array.from(crypto.getRandomValues(new Uint8Array(n)), b => b.toString(16).padStart(2, "0")).join("");
  return `00-${hex(16)}-${hex(8)}-01`;          // eigene Trace-ID; mit OpenTelemetry Web SDK stattdessen dessen Kontext nutzen
}

export function useWorkflow(process: string, caseId: Ref<string | null>) {
  const allowed = ref<AllowedTransition[]>([]);
  const loading = ref(false);
  const rejection = ref<string | null>(null);

  const base = () => `/api/workflows/${encodeURIComponent(process)}/${encodeURIComponent(caseId.value ?? "new")}/transitions`;

  async function load() {
    loading.value = true;
    try {
      const res = await fetch(base(), { headers: { traceparent: traceparent() } });
      allowed.value = res.ok ? await res.json() : [];
    } finally {
      loading.value = false;
    }
  }

  async function transition(to: string, reason?: string): Promise<boolean> {
    rejection.value = null;
    const res = await fetch(base(), {
      method: "POST",
      headers: { "Content-Type": "application/json", traceparent: traceparent() },
      body: JSON.stringify({ to, reason }),
    });
    if (res.status === 409) {                       // vom Backend abgewiesen – als 'rejected' protokolliert
      rejection.value = (await res.json()).detail ?? "Dieser Schritt ist nicht erlaubt.";
      await load();
      return false;
    }
    if (!res.ok) throw new Error(`Statuswechsel fehlgeschlagen: ${res.status}`);
    await load();
    return true;
  }

  return { allowed, loading, rejection, load, transition };
}
