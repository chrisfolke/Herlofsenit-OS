# Herlofsen IT Service — Master Image ("gull-SD-kort")

Oppskrift for å lage ett ferdig tilpasset Anthias-image (med Herlofsen-logo
og sanntids-oppdateringsfiksen bakt inn) som du kan klone til nye SD-kort
for hver kunde.

> **Det viktigste å forstå først:** Anthias kjører i **Docker-containere**.
> Logoen i web-grensesnittet og viewer-fiksen ligger *inne i* container-
> imagene, og en vanlig installasjon laster ned Screenlys ferdige images
> fra `ghcr.io`. Derfor er det **ikke nok** å dra inn en logo-fil med
> WinSCP — endringene må **bygges inn i nye containere** fra denne koden.
> Unntak: selve boot-skjermen (Plymouth) ligger på vertssystemet og kan
> byttes som fil.

---

## Fase 1 — Bygg mester-Pi-en

1. **Installer Anthias normalt** på Pi-en og få den til å kjøre
   (`https://github.com/Screenly/Anthias` installasjonsscript).

2. **Legg den tilpassede koden på Pi-en.** Kopier *denne* mappa (med alle
   endringene) til `/home/<bruker>/anthias` på Pi-en — du kan bruke WinSCP
   til akkurat denne filoverføringen. Erstatt innholdet som install-
   scriptet la der.

3. **Bygg containerne fra den tilpassede koden** (bygger lokalt i stedet
   for å hente Screenlys images):
   ```bash
   cd ~/anthias
   MODE=build bash bin/upgrade_containers.sh
   ```
   > Bygging på en Pi er tregt — regn med 30–60 min, særlig webview-en.
   > Dette baker inn logoen, den kompilerte CSS-en og viewer-fiksen.

4. **Bytt boot-skjermen (Plymouth-splash).** Denne settes på vertssystemet,
   ikke i en container. Enten kjør splashscreen-ansible-rollen på nytt,
   eller bytt fila direkte med WinSCP:
   ```
   /usr/share/plymouth/themes/anthias/splashscreen.png
   ```
   med `ansible/roles/splashscreen/files/splashscreen.png` fra denne koden.
   (Boot-skjermen er satt til hvit bakgrunn + svart tekst så logoen smelter
   inn.)

5. **Test 100 %** at alt virker:
   - Herlofsen-logo på boot-skjerm, på enhetens splash-side (IP/QR) og i
     web-menyen.
   - Oppdaterings-fiksen: bytt et bilde / rediger et element og bekreft at
     skjermen oppdaterer seg **uten** omstart.

---

## Fase 2 — Klargjør for kloning (sysprep)

En rå klon kopierer alle unike hemmeligheter. Kjør derfor dette på
mester-Pi-en **helt til slutt**, rett før avslutning:

```bash
cd ~/anthias
bash bin/prepare_master.sh            # behold spillelisten du satte opp
# eller, for blank kunde-start (sletter assets + nullstiller databasen):
bash bin/prepare_master.sh --wipe-content
```

Scriptet rydder:
- **SSH-nøkler** (`/etc/ssh/ssh_host_*`) — regenereres unikt på første boot.
- **`/etc/machine-id`** — regenereres på første boot.
- **`django_secret_key`** i `anthias.conf` — ny nøkkel mintes på første boot.
- Logger og shell-historikk.
- (med `--wipe-content`) alle assets og hele Anthias-databasen.

Det scriptet **ikke** rører (med vilje):
- **Wi-Fi** — så en headless enhet fortsatt kobler seg på.
- **Admin-innlogging** — så alle dine enheter beholder samme operatør-passord.

> Etter at scriptet er kjørt: **ikke boot mester-Pi-en på nytt før du har
> lest av kortet** — en oppstart ville regenerere nøyaktig de hemmelighetene
> du nettopp tømte.

Slå deretter av rent:
```bash
sudo shutdown -h now
```

---

## Fase 3 — Les av gull-kortet (på Windows-PC-en)

1. Sett SD-kortet i PC-en.
2. Last ned **Win32 Disk Imager** (gratis).
3. Velg en mål-fil, f.eks. `Herlofsen-Smartskilt-v1.img`, og trykk **Read**
   for å lese av hele kortet til `.img`-fila.

---

## Fase 4 — Masseproduksjon (per kunde)

1. Sett inn et **nytt, tomt** SD-kort.
2. Åpne **Raspberry Pi Imager** → «Choose OS» → rull ned → **«Use custom»**.
3. Velg din `Herlofsen-Smartskilt-v1.img` → skriv til kortet.
4. Sett kortet i kundens Pi og slå på. Første boot regenererer unike
   nøkler automatisk.

---

## Fallgruver / tips

- **Kortstørrelse:** `.img`-fila blir like stor som kortet du leste av.
  Gjenopprett alltid til **samme eller større** kort (helst samme modell/
  størrelse). Vil du gjøre fila mindre, kan den krympes med PiShrink på en
  Linux-maskin.
- **Boot-skjerm vises bare på ekte enhet** — kan ikke testes på PC.
- **Ny versjon av produktet:** boot mester-Pi-en igjen, gjør endringer,
  kjør `prepare_master.sh` på nytt, og les av et nytt kort
  (`...-v2.img`).
- **Oppdatere kunder ute i felt:** for det er en egen container-oppdatering
  (`MODE=build`/`pull` via `bin/upgrade_containers.sh`) en bedre vei enn å
  bytte SD-kort fysisk.
