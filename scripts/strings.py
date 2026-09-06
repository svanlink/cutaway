#!/usr/bin/env python3
"""Generate Sources/Cutaway/Localizable.xcstrings from the user-facing literals
in the sources, with German from the table below.

SwiftUI's Text/Button/help/Section/LabeledContent/TextField/Picker/Toggle
already look their literal up as a LocalizedStringKey, so the catalog is the
only thing that has to exist; AppKit strings go through String(localized:).
Keys missing from DE are written untranslated with state "needs_review" so
the gap is visible in Xcode, never silent.

Usage: python3 scripts/strings.py   (idempotent; run after adding UI strings)
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "Cutaway"
OUT = SRC / "Localizable.xcstrings"

# A quoted Swift literal without escapes or interpolation.
LIT = r'"((?:[^"\\]|\\[^(])*)"'
PATTERNS = [
    rf'\bText\({LIT}',
    rf'\bButton\({LIT}',
    rf'\.help\({LIT}',
    rf'\.accessibilityLabel\({LIT}',
    rf'\blabelled\({LIT},\s*{LIT}',
    rf'\bSection\({LIT}',
    rf'\bLabeledContent\({LIT}',
    rf'\bTextField\({LIT}',
    rf'\bPicker\({LIT}',
    rf'\bToggle\({LIT}',
    rf'\bDatePicker\({LIT}',
    rf'\bDisclosureGroup\({LIT}',
    rf'prompt:\s*Text\({LIT}',
    rf'String\(localized:\s*{LIT}',
    rf'\bsupportStat\(key:\s*{LIT}',
]
SKIP = {"", " · ", "＋", "▼", "h:mm", "com.example.app", "%d:%02d", "0.00", "4500", "85"}

DE = {
 "Cancel": "Abbrechen", "Save": "Sichern", "Delete": "Löschen", "Delete…": "Löschen …", "Edit…": "Bearbeiten …",
 "Edit day…": "Tag bearbeiten …", "Edit project": "Projekt bearbeiten", "Edit project…": "Projekt bearbeiten …",
 "Edit project: rate, budget, currency…": "Projekt bearbeiten: Satz, Budget, Währung …",
 "New Project…": "Neues Projekt …", "New Project": "Neues Projekt", "Create Project": "Projekt anlegen",
 "Create your first project": "Erstes Projekt anlegen",
 "Create a project to see stats": "Lege ein Projekt an, um Statistiken zu sehen", "Project name": "Projektname",
 "e.g. Nyx Fashion Film": "z. B. Nyx Fashion Film", "Client": "Kunde", "optional": "optional", "Billing": "Abrechnung",
 "Mode": "Modus", "Hourly": "Stundensatz", "Fixed budget": "Festbudget", "Hourly rate": "Stundensatz", "Budget": "Budget",
 "Currency": "Währung", "Apps": "Apps", "Only these apps count toward this project.": "Nur diese Apps zählen für dieses Projekt.",
 "A new rate applies from now on. Work already recorded keeps the rate it was worked at.": "Ein neuer Satz gilt ab jetzt. Bereits erfasste Arbeit behält den Satz, zu dem sie geleistet wurde.",
 "A project with this name already exists": "Ein Projekt mit diesem Namen existiert bereits",
 "Search apps": "Apps suchen", "Other…": "Weitere …", "Nothing else installed": "Nichts weiter installiert", "No match": "Kein Treffer",
 "Add Time": "Zeit hinzufügen", "Day": "Tag", "Time worked": "Gearbeitete Zeit", "Try 1:30, 1.5 or 90m": "Versuche 1:30, 1.5 oder 90m",
 "Delete the sessions too": "Sitzungen ebenfalls löschen", "Sessions": "Sitzungen",
 "Daily Breakdown": "Tagesübersicht", "＋ Add": "＋ Hinzufügen", "Add time for a day": "Zeit für einen Tag hinzufügen",
 "Includes manual adjustment": "Enthält manuelle Anpassung", "includes manual adjustment": "enthält manuelle Anpassung",
 "Export CSV": "CSV exportieren", "Export project data as CSV": "Projektdaten als CSV exportieren", "Export failed": "Export fehlgeschlagen",
 "EARNED": "VERDIENT", "BUDGET": "BUDGET", "PROJECT TOTAL": "PROJEKT GESAMT", "AVG PER DAY": "Ø PRO TAG", "USED": "VERBRAUCHT",
 "Today": "Heute", "running": "läuft", " active": " aktiv", "Total": "Gesamt", "Total  ": "Gesamt  ",
 "Tracking": "Erfassung", "Idle threshold": "Inaktivitäts-Schwelle", "Timer pauses after this much inactivity": "Der Timer pausiert nach so viel Inaktivität",
 "1 minute": "1 Minute", "2 minutes": "2 Minuten", "5 minutes": "5 Minuten", "10 minutes": "10 Minuten",
 "After a manual pause": "Nach einer manuellen Pause", "When you start editing again in a workflow app": "Wenn du in einer Workflow-App wieder zu schneiden beginnst",
 "Stay paused": "Pausiert bleiben", "Ask me": "Nachfragen", "Resume automatically": "Automatisch fortsetzen",
 "Keep counting during renders": "Während Renderings weiterzählen",
 "Bills export time with no input — only while Resolve is provably busy, max 30 min": "Zählt Exportzeit ohne Eingabe — nur solange Resolve nachweislich arbeitet, max. 30 Min.",
 "Workflow apps": "Workflow-Apps", "Time in these counts toward the project": "Zeit in diesen Apps zählt für das Projekt",
 "Research & comms": "Recherche & Kommunikation", "Research & comms apps": "Recherche- & Kommunikations-Apps",
 "These sustain the timer for 20 minutes after workflow-app activity": "Diese halten den Timer 20 Minuten nach Workflow-App-Aktivität am Laufen",
 "Default hourly rate": "Standard-Stundensatz", "Auto-detected projects start with this rate": "Automatisch erkannte Projekte starten mit diesem Satz",
 "Default currency": "Standardwährung", "New projects start with this currency": "Neue Projekte starten mit dieser Währung",
 "Menu bar & system": "Menüleiste & System", "Menu bar shows": "Menüleiste zeigt", "Which time the pill displays": "Welche Zeit die Pille anzeigt",
 "Current session": "Aktuelle Sitzung", "Project total": "Projekt gesamt",
 "Launch at login": "Beim Anmelden starten", "Start tracking when the Mac starts": "Erfassung starten, wenn der Mac startet",
 "Pause shortcut": "Pause-Kurzbefehl", "⌥⌘P is taken by another app — pause from the panel": "⌥⌘P ist von einer anderen App belegt — pausiere über das Panel",
 "DaVinci Resolve": "DaVinci Resolve", "Accessibility": "Bedienungshilfen", "Lets Cutaway follow Resolve's project switches instantly": "Lässt Cutaway Projektwechseln in Resolve sofort folgen",
 "Granted": "Erteilt", "Enable…": "Aktivieren …", "Not now": "Jetzt nicht",
 "Follow project switches instantly": "Projektwechseln sofort folgen",
 "Cutaway can read Resolve's window title to switch projects the moment you do. It works without this — switching is just slower.": "Cutaway kann Resolves Fenstertitel lesen und Projekte im selben Moment wechseln wie du. Es funktioniert auch ohne — der Wechsel ist nur langsamer.",
 "Bundle id prefixes — e.g. com.adobe.PremierePro": "Bundle-ID-Präfixe — z. B. com.adobe.PremierePro", "Bundle id prefix": "Bundle-ID-Präfix",
 "Add": "Hinzufügen", "Reset to defaults": "Auf Standard zurücksetzen",
 "Pause": "Pause", "Resume": "Fortsetzen", "Pause timer": "Timer pausieren", "Resume timer": "Timer fortsetzen", "Resume tracking": "Erfassung fortsetzen",
 "Looks like you're working": "Sieht aus, als würdest du arbeiten", "Are you working?": "Arbeitest du gerade?",
 "Cutaway is paused, but you're editing.": "Cutaway ist pausiert, aber du schneidest.", "Yes, resume": "Ja, fortsetzen", "No, stay paused": "Nein, pausiert bleiben",
 "Still working?": "Noch dabei?", "I'm still working": "Ich arbeite noch", "Stats ↗": "Statistik ↗", "Settings": "Einstellungen",
 "Open Cutaway": "Cutaway öffnen", "Settings…": "Einstellungen …", "Quit Cutaway": "Cutaway beenden",
 "⚠︎ Data can't be saved this run — time tracked now disappears on quit. Restart Cutaway; if this persists, check disk space.": "⚠︎ Daten können in dieser Sitzung nicht gesichert werden — jetzt erfasste Zeit geht beim Beenden verloren. Starte Cutaway neu; bleibt das Problem, prüfe den Speicherplatz.",
 # v1.3 additions
 "What Cutaway needs, and why": "Was Cutaway braucht, und warum", "Permissions": "Berechtigungen", "Permissions…": "Berechtigungen …",
 "What Cutaway asks for, and what it never does": "Wofür Cutaway fragt — und was es nie tut",
 "Reads Resolve's window title so the project switches when you do. Never controls your Mac.": "Liest Resolves Fenstertitel, damit das Projekt wechselt, wenn du wechselst. Steuert deinen Mac nie.",
 "Automation": "Automatisierung", "Coming with Adobe project names: asks once per app, reads the document name only.": "Kommt mit Adobe-Projektnamen: fragt einmal pro App, liest nur den Dokumentnamen.",
 "Not needed yet": "Noch nicht nötig", "Continue": "Weiter",
 "Cutaway never asks for Screen Recording, never reads keystrokes, and nothing leaves your Mac.": "Cutaway fragt nie nach Bildschirmaufnahme, liest nie Tastatureingaben, und nichts verlässt deinen Mac.",
 "Diagnostics": "Diagnose", "Crash and hang reports stay on this Mac; copy one into a bug report if you want to": "Absturz- und Hänger-Berichte bleiben auf diesem Mac; kopiere einen in einen Fehlerbericht, wenn du möchtest",
 "Copy report": "Bericht kopieren", "Reveal…": "Anzeigen …",
}


# Keys with interpolation — the scan skips "\\(" on purpose; these are the
# catalog keys Swift derives from String(localized:) with an interpolation.
EXTRA = {
 "Research time · %lld min left": "Recherchezeit · noch %lld Min.",
 "Research time · under a minute left": "Recherchezeit · unter einer Minute",
 "Are you working? Cutaway is paused, but you're editing.": "Arbeitest du gerade? Cutaway ist pausiert, aber du schneidest.",
 "Still working? %@": "Noch dabei? %@",
 "Still working? The timer pauses in %lld seconds.": "Noch dabei? Der Timer pausiert in %lld Sekunden.",
 "Last session: %@ · %@": "Letzte Sitzung: %@ · %@",
 "%lld min": "%lld Min.",
 "%@ / day": "%@ / Tag",
 "@ %@ / h": "@ %@ / h",
 "%lld days": "%lld Tage",
 "1 day": "1 Tag",
 "No project selected": "Kein Projekt ausgewählt",
 "%@ today on %@ — %@": "%@ heute an %@ — %@",
 "Total  %@": "Gesamt  %@",
}
DE.update(EXTRA)


def collect() -> set[str]:
    keys: set[str] = set()
    for f in SRC.rglob("*.swift"):
        text = f.read_text(encoding="utf-8")
        for pat in PATTERNS:
            for m in re.finditer(pat, text, flags=re.S):
                for g in m.groups():
                    if g is not None:
                        keys.add(g.replace('\\"', '"'))
    return {k for k in keys if k.strip() and k not in SKIP and "\\(" not in k and not k.startswith("%")} | set(EXTRA)


def main() -> None:
    keys = sorted(collect())
    strings = {}
    translated = 0
    for k in keys:
        de = DE.get(k)
        if de is None:
            strings[k] = {"localizations": {"de": {"stringUnit": {"state": "needs_review", "value": k}}}}
        else:
            translated += 1
            strings[k] = {"localizations": {"de": {"stringUnit": {"state": "translated", "value": de}}}}
    OUT.write_text(json.dumps({"sourceLanguage": "en", "version": "1.0", "strings": strings},
                              ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    missing = [k for k in keys if k not in DE]
    print(f"{len(keys)} keys, {translated} translated → {OUT.relative_to(ROOT)}")
    if missing:
        print("needs_review:", *missing, sep="\n  ")


if __name__ == "__main__":
    main()
