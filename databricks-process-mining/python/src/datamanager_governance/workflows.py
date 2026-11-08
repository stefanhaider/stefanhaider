"""Status-Maschinen des Data Managers – Single Source of Truth für den Workflow (System-Ebene).

Achtung: Das hier ist der SYSTEM-Prozess (was die Applikation zulässt). Der SOLL-Prozess der
Governance liegt getrennt in config/governance_model.json und wird nie aus diesem Code erzeugt.
Abweichungen findet der CI-Check (dm-check-workflow).
"""
from __future__ import annotations

from .events import START
from .state_machine import Workflow

APP_VERSION = "2.5"

ACCESS_REQUEST = (
    Workflow("Access Request")
    .allow(START, "Beantragt")
    .allow("Beantragt", "Prüfung Data Owner")
    .allow("Prüfung Data Owner", "Prüfung Security")
    .allow("Prüfung Data Owner", "Abgelehnt")
    .allow("Prüfung Security", "Berechtigung erteilt")
    .allow("Prüfung Security", "Abgelehnt")
    .allow("Prüfung Data Owner", "Beantragt", note="Rückfrage an Antragsteller")
    .allow("Prüfung Data Owner", "Berechtigung erteilt", since_release="2.3",
           note="Security-Prüfung optional (interne Daten)")
    .allow("Beantragt", "Berechtigung erteilt", note="Express-Vergabe (Feature-Flag, ungenutzt)")
    .end("Berechtigung erteilt", "Abgelehnt")
)

DATA_CONTRACT = (
    Workflow("Data Contract")
    .allow(START, "Entwurf erstellt")
    .allow("Entwurf erstellt", "Schema validiert")
    .allow("Schema validiert", "Review Data Owner")
    .allow("Review Data Owner", "Freigegeben")
    .allow("Review Data Owner", "Verworfen")
    .allow("Freigegeben", "Aktiv")
    .allow("Aktiv", "Änderung beantragt")
    .allow("Änderung beantragt", "Schema erneut validiert")
    .allow("Schema erneut validiert", "Review Änderung")
    .allow("Review Änderung", "Neue Version aktiv")
    .allow("Änderung beantragt", "Neue Version aktiv", note="REST-API: PATCH aktiviert neue Version direkt")
    .end("Aktiv", "Neue Version aktiv", "Verworfen")
)

DATA_PRODUCT = (
    Workflow("Data Product")
    .allow(START, "Angelegt")
    .allow("Angelegt", "Metadaten erfasst")
    .allow("Metadaten erfasst", "Data Contract verknüpft")
    .allow("Data Contract verknüpft", "Qualitätsprüfung")
    .allow("Qualitätsprüfung", "Metadaten erfasst")
    .allow("Qualitätsprüfung", "Freigabe Data Owner")
    .allow("Freigabe Data Owner", "Veröffentlicht")
    .allow("Freigabe Data Owner", "Abgelehnt")
    .allow("Data Contract verknüpft", "Freigabe Data Owner", note="Qualitätsprüfung überspringbar")
    .allow("Metadaten erfasst", "Qualitätsprüfung", note="Data Contract optional")
    .allow("Metadaten erfasst", "Freigabe Data Owner", note="Contract und Qualität überspringbar (ungenutzt)")
    .end("Veröffentlicht", "Abgelehnt")
)

WORKFLOWS = [ACCESS_REQUEST, DATA_CONTRACT, DATA_PRODUCT]
