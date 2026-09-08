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
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "Cutaway"
OUT = Path(os.environ.get("STRINGS_OUT", SRC / "Localizable.xcstrings"))

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
    rf'\.navigationTitle\({LIT}',
    rf'\bWindow\({LIT}',
    rf'LocalizedStringResource = {LIT}',
    rf'shortTitle:\s*{LIT}',
    rf'@Parameter\(title:\s*{LIT}',
    rf'LocalizedStringResource \{{ {LIT}',
    rf'\bhelp:\s*{LIT}',
    rf'\btitle:\s*{LIT}',
    rf'\bline:\s*{LIT}',
]
SKIP = {"", " · ", "＋", "▼", "h:mm", "com.example.app", "%d:%02d", "0.00", "4500", "85"}

DE = {
 "Cancel": "Abbrechen", "Save": "Sichern", "Delete": "Löschen", "Delete…": "Löschen …", "Edit…": "Bearbeiten …",
 "Edit day…": "Tag bearbeiten …", "Edit project": "Projekt bearbeiten", "Edit project…": "Projekt bearbeiten …",
 "Edit project: rate, budget, currency…": "Projekt bearbeiten: Satz, Budget, Währung …",
 "New Project…": "Neues Projekt …", "New Project": "Neues Projekt", "Create Project": "Projekt anlegen",
 "Create your first project": "Erstes Projekt anlegen",
 "Create a project to see stats": "Lege ein Projekt an, um Statistiken zu sehen", "Project name": "Projektname",
 "New project": "Neues Projekt",
 "Not billable": "Nicht abrechenbar",
 "Resolve opened it, and nothing is selected.": "Resolve hat es geöffnet, und nichts ist ausgewählt.",
 "Which project is this?": "Zu welchem Projekt gehört das?",
 "Yes": "Ja",
 "1 session": "1 Sitzung",
 ", running": ", läuft",
 ", tracked": ", erfasst",
 "Day timeline": "Tagesverlauf",
 "Edit": "Bearbeiten",
 "No sessions on this day": "Keine Sitzungen an diesem Tag",
 "Split at a moment inside the session.": "Teile an einem Zeitpunkt innerhalb der Sitzung.",
 "Split in the middle": "In der Mitte teilen",
 ", entered by hand": ", von Hand eingetragen",
 "A session has to end on the day it started. Add a second one after midnight.": "Eine Sitzung muss an dem Tag enden, an dem sie begonnen hat. Trage nach Mitternacht eine zweite ein.",
 "Add a session": "Sitzung hinzufügen",
 "Add session…": "Sitzung hinzufügen …",
 "Earns": "Ergibt",
 "Edit this session": "Diese Sitzung bearbeiten",
 "Length": "Dauer",
 "The end has to come after the start.": "Das Ende muss nach dem Beginn liegen.",
 "The hours follow the span — they are never a separate number": "Die Stunden folgen dem Zeitraum — sie sind nie eine eigene Zahl",
 "Typed time is marked as entered, not tracked — on the day, in the CSV and on the invoice.": "Von Hand eingetragene Zeit wird als eingetragen markiert, nicht als erfasst — am Tag, in der CSV und auf der Rechnung.",
 "—": "—",
 "Asked per app": "Pro App gefragt",
 "Issued": "Ausgestellt",
 "Mark paid": "Als bezahlt markieren",
 "PDF…": "PDF …",
 "Photoshop, Illustrator, InDesign and After Effects are asked for the name of the open document, once each, when you switch to them. Premiere cannot answer and is never asked.": "Photoshop, Illustrator, InDesign und After Effects werden je einmal nach dem Namen des geöffneten Dokuments gefragt, wenn du zu ihnen wechselst. Premiere kann nicht antworten und wird nie gefragt.",
 "The number is kept and never reused, so the sequence stays gapless. Its work becomes billable again and the days unlock.": "Die Nummer bleibt bestehen und wird nie wiederverwendet, damit die Reihenfolge lückenlos bleibt. Die Arbeit wird wieder abrechenbar und die Tage werden entsperrt.",
 "Void": "Stornieren",
 "Void Invoice": "Rechnung stornieren",
 "open the billing store — nothing tracked this run will be kept": "die Abrechnungsdatenbank zu öffnen — nichts aus dieser Sitzung wird gespeichert",
 "A QR reference needs a QR-IBAN. Use a Creditor Reference or none.": "Eine QR-Referenz braucht eine QR-IBAN. Verwende eine Creditor Reference oder keine.",
 "A QR-IBAN requires a QR reference.": "Eine QR-IBAN erfordert eine QR-Referenz.",
 "A payment part with a QR code will be printed. Validate the first one at validation.iso-payments.ch before sending it to a client.": "Ein Zahlteil mit QR-Code wird gedruckt. Prüfe den ersten auf validation.iso-payments.ch, bevor du ihn einem Kunden schickst.",
 "Account / Payable to": "Konto / Zahlbar an",
 "Additional information": "Zusätzliche Informationen",
 "CH93 0076 2011 6238 5295 7": "CH93 0076 2011 6238 5295 7",
 "IBAN": "IBAN",
 "Payable by": "Zahlbar durch",
 "Payment part": "Zahlteil",
 "Receipt": "Empfangsschein",
 "Reference": "Referenz",
 "That IBAN is not a valid Swiss or Liechtenstein IBAN.": "Diese IBAN ist keine gültige Schweizer oder Liechtensteiner IBAN.",
 "That is a QR-IBAN, which needs a bank-issued QR reference. Use your ordinary IBAN instead.": "Das ist eine QR-IBAN; sie braucht eine von der Bank vergebene QR-Referenz. Verwende stattdessen deine gewöhnliche IBAN.",
 "Your IBAN": "Deine IBAN",
 "Address": "Adresse",
 "Amount": "Betrag",
 "An invoice needs your name — fill in the From block above.": "Eine Rechnung braucht deinen Namen — bitte oben unter „Von“ ausfüllen.",
 "An invoice needs your postal address — fill in the From block above.": "Eine Rechnung braucht deine Postadresse — bitte oben unter „Von“ ausfüllen.",
 "Bill": "Abrechnen",
 "Billed to": "Rechnung an",
 "CHE-123.456.789": "CHE-123.456.789",
 "Client UID": "UID des Kunden",
 "Client VAT number": "Mehrwertsteuernummer des Kunden",
 "Client address": "Adresse des Kunden",
 "Could not create the PDF at that location.": "Das PDF konnte an diesem Ort nicht erstellt werden.",
 "Create an invoice": "Rechnung erstellen",
 "EU reverse charge": "EU-Reverse-Charge",
 "From": "Von",
 "Hours": "Stunden",
 "Invoice…": "Rechnung …",
 "Issue & Save PDF…": "Ausstellen & PDF sichern …",
 "Not registered for VAT": "Nicht mehrwertsteuerpflichtig",
 "Nothing unbilled": "Nichts Offenes",
 "Only work that is not already invoiced": "Nur Arbeit, die noch nicht in Rechnung gestellt ist",
 "Outside scope": "Nicht steuerbar",
 "Period": "Zeitraum",
 "Period to bill": "Abzurechnender Zeitraum",
 "Rate": "Satz",
 "Rounded per day, then added": "Pro Tag gerundet, dann addiert",
 "Subtotal": "Zwischensumme",
 "Swiss VAT 8.1 %": "Schweizer MWST 8,1 %",
 "Tax": "Steuer",
 "Tax treatment": "Steuerliche Behandlung",
 "The invoice could not be drawn.": "Die Rechnung konnte nicht gezeichnet werden.",
 "The invoice was issued, but the PDF could not be written": "Die Rechnung wurde ausgestellt, aber das PDF konnte nicht geschrieben werden",
 "This invoice": "Diese Rechnung",
 "To": "An",
 "Total": "Gesamt",
 "UID": "UID",
 "What this client's invoice must state": "Was auf der Rechnung dieses Kunden stehen muss",
 "Your VAT number": "Deine Mehrwertsteuernummer",
 "Your address": "Deine Adresse",
 "Your name": "Dein Name",
 "†": "†",
 "Day": "Tag",
 "h": "Std.",
 "INVOICE": "RECHNUNG",
 "VOID": "STORNIERT",
 "A Swiss VAT invoice must print your UID. Add it in Settings, or choose a different tax mode.": "Eine Rechnung mit Schweizer MWST muss Ihre UID ausweisen. Ergänzen Sie sie in den Einstellungen oder wählen Sie einen anderen Steuermodus.",
 "A reverse-charge invoice must print your UID alongside the client's.": "Eine Rechnung mit Reverse Charge muss Ihre UID neben derjenigen des Kunden ausweisen.",
 "Fixed-price adjustment to agreed budget": "Anpassung auf das vereinbarte Festbudget",
 "No VAT — not registered for Swiss VAT (below the CHF 100'000 threshold).": "Keine MWST — nicht MWST-pflichtig (unter der Grenze von CHF 100'000).",
 "Reverse charge — VAT to be accounted for by the recipient.": "Reverse Charge — die MWST schuldet der Leistungsempfänger.",
 "There is no unbilled work in that period.": "In diesem Zeitraum gibt es keine offene Arbeit.",
 "h": "h",
 "Undo": "Widerrufen",
 "Redo": "Wiederholen",
 "Other apps": "Weitere Apps",
 "Always": "Immer",
 "Always resume automatically": "Immer automatisch fortsetzen",
 "Apps that count": "Apps, die zählen",
 "At launch, daily and at quit — kept on this Mac": "Beim Start, täglich und beim Beenden — bleibt auf diesem Mac",
 "Continue Without Restoring": "Ohne Wiederherstellen fortfahren",
 "Crash and hang reports, kept on this Mac": "Absturz- und Hänger-Berichte, bleiben auf diesem Mac",
 "Cutaway's billing data could not be read": "Cutaways Abrechnungsdaten konnten nicht gelesen werden",
 "Open Backups Folder": "Backup-Ordner öffnen",
 "Pause after no input for": "Pausieren nach Inaktivität von",
 "Raise it if your renders run unattended and you bill them": "Höher setzen, wenn Renders unbeaufsichtigt laufen und berechnet werden",
 "Restore That Backup": "Dieses Backup wiederherstellen",
 "Resume now, and from now on resume without asking": "Jetzt fortsetzen und künftig ohne Nachfrage fortsetzen",
 "That folder does not hold a readable Cutaway backup.": "Dieser Ordner enthält kein lesbares Cutaway-Backup.",
 "These sustain the timer for 20 minutes after work-app activity": "Diese halten die Uhr 20 Minuten nach Aktivität in einer Arbeits-App am Laufen",
 "an unknown number of": "eine unbekannte Anzahl",
 "use the billing store — it is damaged and was left untouched. Nothing tracked this run will be kept.": "die Abrechnungsdatenbank zu verwenden — sie ist beschädigt und wurde unverändert gelassen. Nichts aus dieser Sitzung wird gespeichert.",
 "e.g. Nyx Fashion Film": "z. B. Nyx Fashion Film", "Client": "Kunde", "optional": "optional", "Billing": "Abrechnung",
 "Mode": "Modus", "Hourly": "Stundensatz", "Fixed budget": "Festbudget", "Hourly rate": "Stundensatz", "Budget": "Budget",
 "Currency": "Währung", "Apps": "Apps", "Only these apps count toward this project.": "Nur diese Apps zählen für dieses Projekt.",
 "A new rate applies from now on. Work already recorded keeps the rate it was worked at.": "Ein neuer Satz gilt ab jetzt. Bereits erfasste Arbeit behält den Satz, zu dem sie geleistet wurde.",
 "A project with this name already exists": "Ein Projekt mit diesem Namen existiert bereits",
 "Search apps": "Apps suchen", "Other…": "Weitere …", "Nothing else installed": "Nichts weiter installiert", "No match": "Kein Treffer",
 "Set time for a day": "Zeit für einen Tag festlegen", "The running session alone is longer than that — pause first, then edit.": "Die laufende Sitzung allein ist schon länger — erst pausieren, dann bearbeiten.", "Day": "Tag", "Time worked": "Gearbeitete Zeit", "Try 1:30, 1.5 or 90m": "Versuche 1:30, 1.5 oder 90m",
 "Delete the sessions too": "Sitzungen ebenfalls löschen", "Sessions": "Sitzungen",
 "Daily Breakdown": "Tagesübersicht", "＋ Add": "＋ Hinzufügen", "Add time for a day": "Zeit für einen Tag hinzufügen",
 "Includes manual adjustment": "Enthält manuelle Anpassung", "includes manual adjustment": "enthält manuelle Anpassung",
 "Export CSV": "CSV exportieren", "Export project data as CSV": "Projektdaten als CSV exportieren", "Export failed": "Export fehlgeschlagen",
 "EARNED": "VERDIENT", "BUDGET": "BUDGET", "PROJECT TOTAL": "PROJEKT GESAMT", "AVG PER DAY": "Ø PRO TAG",
 "Today": "Heute", "running": "läuft", " active": " aktiv",
 "Tracking": "Erfassung",
 "1 minute": "1 Minute", "2 minutes": "2 Minuten", "5 minutes": "5 Minuten", "10 minutes": "10 Minuten", "Time in these counts toward the project": "Zeit in diesen Apps zählt für das Projekt",
 "Research & comms": "Recherche & Kommunikation",
 "Default hourly rate": "Standard-Stundensatz", "Auto-detected projects start with this rate": "Automatisch erkannte Projekte starten mit diesem Satz",
 "Default currency": "Standardwährung", "New projects start with this currency": "Neue Projekte starten mit dieser Währung",
 "Menu bar & system": "Menüleiste & System",
 "Launch at login": "Beim Anmelden starten", "Start tracking when the Mac starts": "Erfassung starten, wenn der Mac startet",
 "Pause shortcut": "Pause-Kurzbefehl", "⌥⌘P is taken by another app — pause from the panel": "⌥⌘P ist von einer anderen App belegt — pausiere über das Panel",
 "DaVinci Resolve": "DaVinci Resolve", "Accessibility": "Bedienungshilfen",
 "Granted": "Erteilt", "Enable…": "Aktivieren …", "Not now": "Jetzt nicht",
 "Follow project switches instantly": "Projektwechseln sofort folgen",
 "Cutaway can read Resolve's window title to switch projects the moment you do. It works without this — switching is just slower.": "Cutaway kann Resolves Fenstertitel lesen und Projekte im selben Moment wechseln wie du. Es funktioniert auch ohne — der Wechsel ist nur langsamer.", "Reset to defaults": "Auf Standard zurücksetzen",
 "Pause": "Pause", "Resume": "Fortsetzen", "Pause timer": "Timer pausieren", "Resume timer": "Timer fortsetzen", "Resume tracking": "Erfassung fortsetzen",
 "Looks like you're working": "Sieht aus, als würdest du arbeiten", "Are you working?": "Arbeitest du gerade?",
 "Cutaway is paused, but you're editing.": "Cutaway ist pausiert, aber du schneidest.", "Yes, resume": "Ja, fortsetzen", "No, stay paused": "Nein, pausiert bleiben",
 "Still working?": "Noch dabei?", "I'm still working": "Ich arbeite noch", "Stats ↗": "Statistik ↗", "Settings": "Einstellungen",
 "Open Cutaway": "Cutaway öffnen", "Settings…": "Einstellungen …", "Quit Cutaway": "Cutaway beenden",
 "⚠︎ Data can't be saved this run — time tracked now disappears on quit. Restart Cutaway; if this persists, check disk space.": "⚠︎ Daten können in dieser Sitzung nicht gesichert werden — jetzt erfasste Zeit geht beim Beenden verloren. Starte Cutaway neu; bleibt das Problem, prüfe den Speicherplatz.",
 # v1.3 additions
 "What Cutaway needs, and why": "Was Cutaway braucht, und warum", "Permissions": "Berechtigungen",
 "Reads Resolve's window title so the project switches when you do. Never controls your Mac.": "Liest Resolves Fenstertitel, damit das Projekt wechselt, wenn du wechselst. Steuert deinen Mac nie.",
 "Automation": "Automatisierung", "Coming with Adobe project names: asks once per app, reads the document name only.": "Kommt mit Adobe-Projektnamen: fragt einmal pro App, liest nur den Dokumentnamen.",
 "Not needed yet": "Noch nicht nötig", "Continue": "Weiter",
 "Cutaway never asks for Screen Recording, never reads keystrokes, and nothing leaves your Mac.": "Cutaway fragt nie nach Bildschirmaufnahme, liest nie Tastatureingaben, und nichts verlässt deinen Mac.",
 "Diagnostics": "Diagnose", "Choose app…": "App auswählen …", "No editing apps found in /Applications — choose one below.": "Keine Schnitt-Apps in /Applications gefunden — wähle unten eine aus.", "Couldn't change Launch at login": "„Beim Anmelden starten“ konnte nicht geändert werden", "Data": "Daten", "Backups": "Sicherungen", "Restore…": "Wiederherstellen …", "No backup yet": "Noch keine Sicherung", "Choose a backup folder. Cutaway will relaunch with it.": "Wähle einen Sicherungsordner. Cutaway startet damit neu.", "Couldn't stage that backup": "Diese Sicherung konnte nicht vorbereitet werden", "Restore and relaunch?": "Wiederherstellen und neu starten?", "The current store is kept beside the restored one. Time tracked since that backup is not in it.": "Der aktuelle Speicher bleibt neben dem wiederhergestellten erhalten. Seit dieser Sicherung erfasste Zeit ist nicht enthalten.", "Restore and Relaunch": "Wiederherstellen und neu starten", "The backup you chose has been restored.": "Die gewählte Sicherung wurde wiederhergestellt.", "Cutaway": "Cutaway", "Cutaway Settings": "Cutaway-Einstellungen", "Welcome to Cutaway": "Willkommen bei Cutaway", "Pause Cutaway": "Cutaway pausieren", "Resume Cutaway": "Cutaway fortsetzen", "Today's Time in Cutaway": "Heutige Zeit in Cutaway", "Switch Cutaway Project": "Cutaway-Projekt wechseln", "Cutaway is not running yet": "Cutaway läuft noch nicht", "Reveal…": "Anzeigen …",
}


# Keys with interpolation — the scan skips "\\(" on purpose; these are the
# catalog keys Swift derives from String(localized:) with an interpolation.
EXTRA = {
 "Research time · %lld min left": "Recherchezeit · noch %lld Min.",
 "Research time · under a minute left": "Recherchezeit · unter einer Minute",
 "Are you working? Cutaway is paused, but you're editing.": "Arbeitest du gerade? Cutaway ist pausiert, aber du schneidest.",
 "Still working? %@": "Noch dabei? %@",
 "No project named %@": "Kein Projekt namens %@",
 "Now tracking %@": "Jetzt wird %@ erfasst",
 "Last backup %@": "Letzte Sicherung %@",
 "The billing store was damaged; the backup %@ was restored. The damaged file is kept beside it.": "Der Abrechnungsspeicher war beschädigt; die Sicherung %@ wurde wiederhergestellt. Die beschädigte Datei bleibt daneben erhalten.",
 "Diagnostics folder unreadable: %@": "Diagnose-Ordner nicht lesbar: %@",
 "Edit %@": "%@ bearbeiten",
 "Set an hourly rate on the project to edit by amount": "Lege im Projekt einen Stundensatz fest, um nach Betrag zu bearbeiten",
 "Amount · %@": "Betrag · %@",
 "@ %@ %@ / h — one value, two views": "@ %@ %@ / h — ein Wert, zwei Ansichten",
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
    print(f"{len(keys)} keys, {translated} translated → {OUT}")
    if missing:
        print("needs_review:", *missing, sep="\n  ")
    # German that no source literal reaches is a string the scan missed —
    # the primer shipped in English this way once. Loud, not silent.
    orphans = sorted(set(DE) - set(keys))
    if orphans:
        print("orphans (in DE, not in sources):", *orphans, sep="\n  ")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
