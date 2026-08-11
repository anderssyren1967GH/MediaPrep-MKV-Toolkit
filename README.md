## CPU/GPU-layout 0.11.51

Hotfix för WinForms-ankring: kontrollknapp, uppdateringsknapp, progressbar och högra detaljpanelen är vänsterankrade inom Videoencoder-gruppen så de inte flyttas utanför det synliga området när layouten expanderar.

## CPU/GPU-layout 0.11.50

CPU/GPU-fliken visar kontrollknapp, encoderöversikt och en separat detaljpanel med benchmark/capability-resultat. Processdiagnostiken i bannern visas i två kolumner.

## Verktygsversioner och processdiagnostik 0.11.49

Bannern visar aktiv FFmpeg- och MKVToolNix-version samt namn/PID för Start Center och dess levande underprocesser. Det gör det lättare att se om exempelvis en köhost, FFmpeg eller annan MediaPrep-startad process fortfarande körs.

Under **Inställningar → Kontrollera / hämta externa verktyg** kan FFmpeg och MKVToolNix väljas online bland upp till de fem senaste tillgängliga stabila versionerna. Den befintliga aktiva versionen säkerhetskopieras alltid lokalt före byte. FFmpeg-versionen kompatibilitetstestas innan aktivering; efter ett FFmpeg-byte krävs ny CPU/GPU-kontroll.

CPU/GPU-kontrollknappen finns endast på fliken **CPU/GPU**.

## CPU/GPU och verifierad HEVC-encoder 0.11.46

Flikordningen är **Översikt | Val | CPU/GPU | Inställningar**. En ny installation väljer CPU/libx265 som standard, men MediaPrep tillåter inte att kön startas förrän en CPU/GPU-kontroll har genomförts. Kontrollen identifierar installerad hårdvara och kör verkliga korta HEVC-testkodningar. Endast encoderalternativ som klarat testet kan väljas.

Stödda backend-kandidater är CPU `libx265`, NVIDIA `hevc_nvenc`, Intel (inklusive kompatibel Arc/iGPU) `hevc_qsv` och AMD/Radeon `hevc_amf`. Hårdvara som inte finns i datorn visas inte som valbar encoder. Flera verifierade alternativ kan växlas när kön är stoppad.

Benchmarken använder samma reproducerbara 1080p-testsekvens och visar hastighet, SSIM och teststorlek. NVIDIA-testet visar dessutom VRAM och belastningsdata när `nvidia-smi` kan läsa dem. VRAM är informationsvärde och kan inte allokeras manuellt från MediaPrep. Encoder-/capability-resultaten sparas under `Data` och blir automatiskt inaktuella när FFmpeg, GPU eller grafikdrivrutin ändras.

## Säker uppdatering och rollback av externa verktyg 0.11.43

Verktygshanteraren säkerhetskopierar en befintlig FFmpeg- eller MKVToolNix-installation till `Tools\ToolBackups` innan en ny version aktiveras. Ny FFmpeg byggs/stagas och kontrolleras innan den ersätter den aktiva versionen. Om aktiveringen misslyckas återställs föregående lokala version. Menyalternativet **Versioner/återställ** kan användas för att välja bland sparade lokala versioner. När FFmpeg ändras kräver MediaPrep en ny CPU/GPU-kontroll.

## Startläge, UAC och köpaket 0.11.41

MediaPrep startar normalt utan elevation. Endast det sparade valet att förhindra automatisk Windows Update-omstart under en kö kräver administratörsrättigheter. När valet aktiveras och sparas (med kön stoppad) sparas aktuell arbetslista och Start Center startas om via UAC. Spara/Öppna kö fungerar i både Kö och Allt i ett.


## Session, sparade köer och historisk statistik 0.11.39

- Sessionsklockan startar först när **Starta hela kön** verkligen startas och pausas när köprocessen avslutas/stoppas. Tom Start Center-tid räknas inte.
- Alla UNC-köer som finns vid start registreras direkt i `statistics-run-current.json`; ytterligare köer kan läggas till senare under samma session.
- Kömonitorn har **Ladda statistik...** för arkiverade `Data\Statistics\statistics-run-*.json` och **Aktuell** för att återgå till live-sessionen. Arkivläget visar även kvarvarande filer, fel och långsamma kopieringar från sessionsfilen.
- Start Center har **Spara kö** och **Öppna kö**. Ett sparat ZIP-paket innehåller kölista samt relevanta runtime-JSON-filer och befintlig sessionsstatistik.
- Vid uppstart upptäcks en kvarlämnad/ofärdig `statistics-run-current.json`. Användaren kan välja **Fortsätt**, **Spara till senare** eller **Ta bort**. Mediefiler och UNC-original raderas inte av detta val.

# MediaPrep MKV Toolkit 0.11.51

## Kataloglayout från 0.11.38

```text
MediaPrep MKV Toolkit\
├─ Start MediaPrep.cmd
├─ README.md
├─ CHANGELOG.md
├─ LICENSE.md
├─ THIRD-PARTY-NOTICES.md
├─ App\
│  ├─ MediaPrep-Start.ps1
│  ├─ MediaPrep.ps1
│  ├─ MediaPrep-Queue.ps1
│  ├─ MediaPrep-Queue-Host.ps1
│  ├─ MediaPrep-Queue-Dashboard.ps1
│  ├─ MediaPrep-Encoder-Test.ps1
│  ├─ Manage-MediaPrepTools.ps1
│  └─ Install-MediaPrep.ps1
├─ Data\
│  ├─ config.json
│  ├─ mediaprep.preferences.json
│  ├─ Temp\
│  ├─ Downloads\
│  └─ Statistics\
├─ Error\
├─ Installer\
├─ Languages\
├─ Loggar\
├─ Processed\
├─ Rapporter\
├─ Tools\
│  └─ ToolBackups\
└─ UnProcessed\
```

Starta alltid programmet med `Start MediaPrep.cmd`. Vid första start efter uppgradering från äldre layout flyttas gamla PowerShell-skript i rotmappen till en säker backup under `Data\LegacyLayoutBackup_*`.

## Sessionsstatistik 0.11.38
`Data\statistics-run-current.json` lever under hela tiden Start Center är öppet. Varje faktisk kopiering lagras som en separat copy-event, så återkörningar och nytillagda köer räknas korrekt i sessionens totala in-/utdata och MB/s. Dashboard-loggen skapas alltid för fel och varningar även när Verbose är avstängt.

Updated in 0.11.20: queue statistics are shown in a dedicated fixed dashboard box and stall diagnostics are clarified.

Updated in 0.11.18: queue statistics remain visible in Queue mode, and verbose diagnostics now capture FFmpeg/NVENC/GPU details for troubleshooting.

Updated in 0.11.17: queue statistics are always visible and update live while folders are scanned or queue items change.

﻿## 0.11.15

Start Center verifies every UNC queue folder before a run. If the elevated MediaPrep session lacks SMB access it prompts for credentials, connects in that elevated session, then verifies read/write/delete access. Queue mode shows four persistent statistics: remaining files, processed/total, remaining size and ready-to-return files.

Updated in 0.11.14: queue statistics panel on Dashboard and improved cleanup of empty Processed folders.

Updated in 0.11.12: live NVENC progress is shown in the blue PowerShell progress area and logged every five seconds.

## Nytt i 0.11.11

- NVENC-progress visas löpande i PowerShells progressruta och loggas var femte sekund.
- Återkopiering till UNC visar kopierad mängd, procent och beräknad återstående tid.
- Tomma lokala kömappar rensas efter lyckad bearbetning, även efter återstart.

Updated in 0.11.8: restart-safe UNC imports avoid copying files again when a matching MKV already exists, reuse complete local sources, and reprocess interrupted items.

Updated in 0.11.7: fixes PowerShell 5.1 path/program status validation.

﻿Updated in 0.11.6: all configured folders and external programs now show a green check or red cross, with a unified Check paths / programs action.

Updated in 0.11.5: fixes a StrictMode startup error in the Preferences tool status initialization.

Updated in 0.11.4: Preferences layout refined, external tools heading moved to the left pane, and the right pane now focuses on language and tool controls.

﻿# MediaPrep MKV Toolkit 0.11.0

Created by Anders Syrén.

MediaPrep MKV Toolkit is a Windows PowerShell 5.1 workflow for muxing TS/MP4/AVI/MPG/MPEG files to MKV, handling subtitles, analyzing media, optionally reducing file size with a verified CPU/NVIDIA/Intel/AMD HEVC encoder, processing UNC queues, and organizing completed media.

**Source available for personal, non-commercial use.** See `LICENSE.md`.

## PowerShell-first project

The project intentionally remains PowerShell-based. There is no compiled application executable, which keeps the source readable and makes it easier for others to maintain or extend the project later.

## Default folders

- `UnProcessed` — local TS/MP4/AVI/MPG/MPEG files waiting to be processed
- `Processed` — completed MKV files
- `Data` — settings, indexes, manifests, and queue state
- `Data\Temp` — temporary working files
- `Data\Downloads` — reserved for future tool downloads
- `Loggar` — logs
- `Rapporter` — reports
- `Languages` — `.local` language files
- `Tools\FFmpeg` — reserved for a user-managed FFmpeg installation
- `Tools\MKVToolNix` — reserved for a user-managed MKVToolNix installation

All folders are included in GitHub/ZIP distributions. `.gitkeep` files are used because Git does not track empty directories.

Existing installations that explicitly use the older `Filmer` folder continue to work. New installations use `UnProcessed`.

## Install from a downloaded GitHub release

Extract the release and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\Install-MediaPrep.ps1
```

A folder picker lets the user choose the installation location. The installer copies the PowerShell source and creates the complete folder structure. It does not install FFmpeg or MKVToolNix binaries.

## Portable use

Extract the ZIP anywhere and start:

```text
Start MediaPrep.cmd
```

Configure external tools under Preferences.


## External tools

The repository does not include FFmpeg or MKVToolNix binaries. Use **Preferences → Check / download external tools** to verify, download or update them. FFmpeg is obtained from a Windows build provider linked by the FFmpeg project; MKVToolNix is obtained from its project download site.


## Preferences fixes in 0.11.3

The executable file picker starts in the currently configured tool directory. The language selector remains visible at the bottom of Preferences.


## Externa verktyg

Standardplaceringar:

```text
Tools\FFmpeg\ffmpeg.exe
Tools\FFmpeg\ffprobe.exe
Tools\MKVToolNix\mkvmerge.exe
```

Språk och verktygshantering finns i högra delen av Preferences.


## AVI-stöd i 0.11.26
AVI-filer behandlas som övriga källfiler. MediaPrep kör ffprobe före muxning för att verifiera och dokumentera container, codecs, upplösning, FPS, pixel format, längd, bitrate och strömmar. Därefter muxas filen till MKV utan omkodning när det är möjligt och går vidare till den vanliga analysen och eventuell HEVC-omkodning med vald verifierad encoder.


## Kömonitor och verbose-logg i 0.11.27

Kömonitorn startas automatiskt när kön startas. Om **Verbose logging** är aktivt skrivs en separat dashboard-logg till `Loggar\MediaPrep-Queue-Dashboard_YYYY-MM-DD_HH-mm-ss.log` samt en launcher-logg för själva processstarten.


## Fönsterhantering i 0.11.29

- Start Centers egna PowerShell-konsol döljs automatiskt.
- Kömonitorns PowerShell-konsol döljs automatiskt.
- Det detaljerade köfönstret startar dolt och kan växlas med **Visa detaljer / Dölj detaljer** i kömonitorn.
- **Visa statistik** finns även i Inställningar under Programinställningar.
- Verbose-loggning fortsätter till fil även när konsolfönstren är dolda.


## Manuella åtgärder i felkön (0.11.30)

I Kömonitor > Felkö kan en markerad post granskas, fortsättas eller tas bort. **Granska** öppnar lokal MKV. **Fortsätt** återställer posten till bästa säkra QueueStage och tar bort felmarkeringen. **Ta bort** tar bort posten ur MediaPrep-kön och rensar endast lokala arbets-/tempfiler; originalet på UNC lämnas orört.


### Köisolering (0.11.35)
I Kö-läge bearbetas varje UNC-mapp helt färdigt innan nästa köpost startar: import -> mux -> analys -> eventuell NVENC -> återflytt -> lokal städning. Skanning och analys filtreras till filer som hör till aktuell köpost.


## Sessionsstatistik (0.11.35)
`Data\statistics-run-current.json` skapas när Start Center startar och summerar alla köer/filer under hela den aktuella MediaPrep-sessionen. Filen arkiveras till `Data\Statistics` när Start Center stängs. Köstatusen ligger fortsatt i `queue-dashboard-inventory.json`.


## Themes (0.11.42)
Under **Inställningar** kan gränssnittstema väljas som Ljus, Mörk, Per månad eller Custom. Per månad använder en automatisk färgpalett baserad på aktuell månad. Custom använder tre sparade hex-färger för banner, panel/accent och bakgrund.
