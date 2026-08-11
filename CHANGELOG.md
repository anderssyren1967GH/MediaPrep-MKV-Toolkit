## 0.11.51 - 2026-08-11

- CPU/GPU-layout: rättar WinForms-ankring som flyttade Kontrollera CPU/GPU, Uppdatera maskinvara, progressbaren och detaljpanelen långt utanför den synliga delen när containern ändrade storlek.
- De berörda kontrollerna är nu vänsterankrade och behåller sina avsedda positioner: kontrollknapp X=682, uppdateringsknapp X=900 och detaljpanel X=682.
- Ingen ändring i encoder-test, capability-cache, benchmark, kömotor, muxning, omkodning, UNC-flöde eller statistik.

## 0.11.50 - 2026-08-11

- CPU/GPU: kontrollknappen görs explicit synlig och ligger endast på CPU/GPU-fliken.
- CPU/GPU: detaljpanelen är nu en egen GroupBox som alltid visar benchmark och capability-resultat för vald eller aktuell testad encoder.
- Banner: MediaPrep-processer visas i två kolumner med namn och PID för bättre läsbarhet.

# MediaPrep MKV Toolkit changelog

## 0.11.49 - 2026-08-11
- CPU/GPU-kontrollen finns nu endast på fliken **CPU/GPU**. Den globala kontrollknappen i Start Centers nederkant är borttagen.
- Bannern visar installerad **FFmpeg-version** och **MKVToolNix-version**.
- Bannern visar löpande namn och PID för Start Center-processen och alla levande underprocesser som startats från den, t.ex. PowerShell, FFmpeg, ffprobe och mkvmerge. Processlistan uppdateras ungefär var femte sekund.
- Verktygshanteraren kan nu hämta och välja bland de fem senaste tillgängliga stabila FFmpeg-versionerna online. Vald version stagras och kompatibilitetstestas innan den aktiveras.
- Verktygshanteraren kan välja bland de fem senaste MKVToolNix-versionerna online.
- Befintlig lokal rollback är kvar: den aktiva versionen säkerhetskopieras före byte, så en tidigare fungerande FFmpeg/MKVToolNix kan återställas även efter att en annan onlineversion installerats.
- **A / alla** installerar den senaste versionen av båda verktygen; **F** respektive **M** öppnar versionsvalet.
- Byte av FFmpeg ogiltigförklarar fortsatt CPU/GPU-kontrollen så encoders verifieras på nytt mot den valda FFmpeg-versionen.
- Ingen ändring i köisolering, muxning, analys, omkodningsalgoritm, felkö, sessionsstatistik eller UNC-återflyttning.

## 0.11.45 - 2026-08-11
- CPU/GPU-fliken visar nu även identifierade NVIDIA-, Intel- och AMD-encoderkandidater **före** första kontrollen. De markeras tydligt som `Ej kontrollerad`; de blir inte godkända eller sparade som aktiv encoder förrän det verkliga benchmark-/capability-testet har klarats.
- När en köstart blockeras därför att CPU/GPU ännu inte kontrollerats växlar Start Center till CPU/GPU-fliken och sätter fokus på **Kontrollera alla encoders**.
- Start Center har fast fönsterstorlek och kan inte längre dras ihop så att CPU/GPU-knappar, flikar eller nederkantens kontroller hamnar utanför den synliga layouten. Vanlig minimering till aktivitetsfältet är fortfarande möjlig.
- Encoder-, kö-, mux-, analys-, statistik-, tema-, UAC- och verktygshanteringslogik är i övrigt oförändrad.

## 0.11.44 - 2026-08-11
- Hotfix: Start Center kunde inte öppnas på grund av felaktig användning av PowerShells `-f`-operator i CPU/GPU-flikens text för fysiska kärnor/logiska processorer.
- CPU-raden formateras nu innan den skickas till `List.Add()`, så hårdvarusammanfattningen inte kan ge `FormatError` vid uppstart.
- Ingen kö-, mux-, analys-, NVENC/QSV/AMF-, statistik-, UAC-, tema- eller verktygshanteringslogik har ändrats i denna hotfix.

## 0.11.43 - 2026-08-11
- Ny flik **CPU/GPU** mellan Val och Inställningar. Den visar upptäckt CPU/GPU, drivrutiner, verifierade HEVC-encoders och benchmarkresultat.
- Första installationen väljer CPU/libx265 som standard. En riktig CPU/GPU-kontroll måste genomföras innan en kö får starta.
- Encoder-kontrollen kör reproducerbara 1080p-testkodningar och verifierar endast de backends som både finns i FFmpeg och på installerad hårdvara: CPU/libx265, NVIDIA/hevc_nvenc, Intel/hevc_qsv och AMD/hevc_amf.
- Flera verifierade encoderalternativ kan väljas i dropdown när kön är stoppad. Encoder kan inte bytas medan en kö arbetar.
- Benchmark visar hastighet, SSIM och teststorlek. För NVIDIA mäts dessutom VRAM före/max/ökning, GPU-/encoderbelastning och temperatur när `nvidia-smi` finns. VRAM visas endast som diagnostik och är inte användarstyrt.
- NVIDIA capability-test provar bland annat CUDA decode, preset P4, VBR/CQ, Spatial AQ, Temporal AQ, lookahead, surfaces och multipass. Funktioner som inte klarar det verkliga testet markeras som ej stödda. Huvudkodningen behåller den konservativa/stabila NVENC-profilen och aktiverar inte nya extrafunktioner automatiskt.
- Encoder-resultat sparas i `Data\encoder-capabilities.json` och `Data\encoder-benchmark.json`. Kontrollresultatet blir inaktuellt om FFmpeg-version, GPU-lista eller grafikdrivrutin ändras.
- Bannern visar vald encoder dynamiskt, t.ex. CPU HEVC, NVIDIA HEVC NVENC, Intel HEVC QSV eller AMD HEVC AMF.
- FFmpeg- och MKVToolNix-uppdateringar säkerhetskopierar nu den aktiva versionen under `Tools\ToolBackups`. Verktygshanteraren har **Versioner/återställ** och kan återställa en tidigare lokal version om en uppdatering orsakar problem.
- FFmpeg uppdateras i staging och verifieras innan aktivering. Misslyckad aktivering återställer föregående version automatiskt. Byte av FFmpeg ogiltigförklarar CPU/GPU-kontrollen.
- Custom-temats tre hex-fält har kompakta live-färgprover bredvid respektive värde. Färgprovet ändras direkt när ett giltigt `#RRGGBB` skrivs. Sparade Custom-färger startar om Start Center när kön är stoppad så temat appliceras direkt.
- Gröna/röda sökvägs- och programstatusmarkeringar återställs efter temaläggning så statusfärgerna behåller sin semantiska betydelse.
- Tema-/språkomstarten går genom ordinarie UAC-startlogik, så ett sparat Windows Update-skydd tappar inte elevation efter ett temabyte.
- Arbetskö, köisolering, felkö, sessionsstatistik, sparade köpaket, UAC/Windows Update-skydd, filformat och dashboard har lämnats orörda utöver att vald encoder förs genom jobbfilen.

## 0.11.42
- Arbetskön använder en enda vertikal knapprad i både Kö och Allt i ett.
- Ny temaväljare under Inställningar: Ljus, Mörk, Per månad och Custom.
- Per månad väljer automatiskt den färgpalett som hör till aktuell månad.
- Custom sparar tre hex-färger: banner, sekundär/panel och bakgrund.
- Temat används även av kömonitorn/statistikfönstret.

## 0.11.41 - 2026-08-11
- UI: omarkerade kryssrutor och radioknappar visas med grå text men är fortsatt klickbara; markerade val visas svart.
- UAC: Windows Update-skyddet kan väljas även när Start Center inte är eleverat; UAC begärs först när valet sparas.
- UI: UAC-sköld visas framför Windows Update-skyddet.
- Arbetskö: "Ladda..." har bytt namn till "Lägg till i kön" / "Add to queue".
- Arbetskö: Loggar-knappen har flyttats från Kö/Allt i ett till Inställningar under Visa statistik.
- Kömonitor: bottenradens status och knappar överlappar inte längre; Visa/Dölj detaljer visas fullt ut vid resize.

## 0.11.40 - 2026-08-11

- Allt i ett: städad tvåkolumnslayout för arbetsköknappar så kontroller inte överlappar eller klipps.
- Spara kö / Öppna kö finns nu i både Kö och Allt i ett.
- Val-fliken omdisponerad: körläge och omkodningskriterier överst, övriga val samlade under.
- UAC: MediaPrep startar normalt utan administratörsrättigheter. Elevation begärs endast när användaren uttryckligen sparat "Förhindra automatisk Windows Update-omstart under kön".
- Första uppstarten har Windows Update-omstartsskydd avstängt.
- När skyddet aktiveras och valen sparas startas Start Center om via UAC; aktuell kölista sparas före omstarten.
- Windows Update-skydd kan inte ändras/sparas under pågående kö; användaren får ett tydligt meddelande i stället för omstart.
- Arkivstatistik: gamla stage 8/9-poster med dokumenterat lyckad returkopiering rekonstrueras som klara, vilket stabiliserar progressbaren och "Klara".
- Sessionsstatistik: en Out-copy markerar inte längre Result=Completed innan QueueStage 10 faktiskt har skrivits.

## 0.11.39 - 2026-08-11

- Sessionsklockan startar först när kön startas och räknar endast aktiv kötid; den tickar inte bara för att Start Center är öppet.
- Samtliga köer registreras i sessionsstatistiken vid start, inte först när respektive kö börjar behandlas.
- Statistikfönstrets gamla `Uppdatera nu` ersätts av **Ladda statistik...** och **Aktuell**. Arkiverade statistics-run JSON kan visas inklusive kvar/fel/långsamma kopieringar.
- Start Center får **Spara kö** och **Öppna kö**. Köpaketet är ZIP och innehåller relevanta JSON-filer inklusive sessionsstatistik.
- Vid uppstart detekteras en ofärdig session och användaren får välja Fortsätt, Spara till senare eller Ta bort.
- Sessionsfilen arkiveras först när Start Center stängs normalt och ingen köprocess fortfarande körs.

## 0.11.38 - 2026-08-10

- Rättar dashboard-fel på stora bytevärden över Int32-gränsen (2 147 483 647).
- Utrymmesbesparing beräknas nu med Double/64-bitars storleksvärden utan Math.Max(Int32)-överlagring.
- Dashboarden kan därför fortsätta uppdatera statistik för stora köer/filer utan felet "Cannot convert ... to System.Int32".

## 0.11.36 - 2026-08-10
- Ny ren kataloglayout: körbara PowerShell-skript ligger under `App\`; rotmappen innehåller endast launcher och dokumentation.
- `config.json` och `mediaprep.preferences.json` ligger under `Data\`.
- Start Center migrerar automatiskt äldre rot-skript till `Data\LegacyLayoutBackup_*` och flyttar äldre konfigurationsfiler till `Data\` när det behövs.
- Alla interna sökvägar har gåtts igenom för App/Data-layouten: Start Center, Queue Host, Queue, Dashboard, MediaPrep, verktygshanteraren, installeraren och felkö-batchen.
- Sessionsstatistiken lagrar varje faktisk kopiering som en `CopyEvent`; om samma fil kopieras igen under samma session räknas även den nya överföringen.
- `Totalt kopierat från UNC`, `Totalt kopierat tillbaka`, kopieringstid och MB/s summeras från hela sessionens copy-events.
- Dashboardens huvud-progressbar visar klara filer / alla registrerade filer i hela sessionen.
- Dashboard-logg skapas alltid för INFO/WARN/ERROR; Verbose lägger endast till VERBOSE-rader.
- JSON-skrivningar i huvudmotorn och Start Center görs atomiskt via temporär fil för att minska risken att dashboarden läser en halvskriven sessions-/köfil.
- Installeraren kopierar endast programfiler och standardkonfiguration, aldrig befintliga media-, logg-, kö- eller statistikdata.

# Changelog

## 0.11.35 - 2026-08-10
- Ny sessionsbaserad statistikfil: `Data\statistics-run-current.json`.
- Statistiksessionen skapas när Start Center öppnas och lever över flera kökörningar tills Start Center stängs.
- Varje UNC-kö och fil läggs till i samma sessionsfil med kopiering in/ut, storlekar, resultat och köstatus.
- Körningsstatistik-fliken använder sessionsfilen som sanningskälla och nollställs därför inte mellan enskilda UNC-köer.
- `Snitt in` och `Snitt tillbaka` beräknas som total MB / faktisk total kopieringstid för hela sessionen.
- När Start Center stängs arkiveras sessionen under `Data\Statistics`.
- Om en gammal current-fil hittas vid start bevaras den som en recovered-session innan en ny session skapas.

## 0.11.35

- UNC-köer är nu strikt isolerade: en köpost kopieras, muxas, analyseras, omkodas och återförs innan nästa köpost startar.
- Scan-MediaLibrary begränsas i köläge till endast de lokala källfiler som importerades för aktuell UNC-kö.
- MKV-analys och NVENC-rekommendation begränsas till endast ExpectedOutput-filer som tillhör aktuell UNC-kö.
- Gamla/återupptagna lokala filer från andra köposter får inte längre dras in i aktuell bearbetning.
- Detta minskar risken att UnProcessed/Processed fyller lokal disk när många UNC-mappar ligger i kön.

## 0.11.33

- Rättar ett köstopp där en trasig eller gammal lokal AVI/MPG/MPEG/TS/MP4 i `UnProcessed` kunde avbryta alla efterföljande UNC-köer under ffprobe-steget.
- `ffprobe` startas nu via `System.Diagnostics.Process`, så stderr från en ogiltig mediefil inte blir ett oavsiktligt `NativeCommandError` i Windows PowerShell 5.1.
- Om ffprobe inte kan analysera en lokal källfil flyttas arbetskopian till `Error`, registreras som `SourceProbe` i felkön och huvudkön fortsätter med nästa fil. UNC-originalet påverkas inte.
- Felorsaken innehåller nu ffprobes verkliga exitkod och feltext för enklare felsökning.

## 0.11.32
- Rättar falska "UNC-kopian saknar videospår" för giltiga MPG/MPEG->MKV genom ffprobe JSON-verifiering.
- Skiljer på ffprobe-fel och verkligt saknat video-/ljudspår.
- Fel vid UNC-återflyttning sparar ErrorKind/PreviousStage/LocalPath så lokal fungerande MKV kan granskas.
- "Fortsätt" återställer publiceringsfel till QueueStage 8 (Väntar återflytt) i stället för att muxa/analysera om.
- Felkö-knapparna ligger i en egen dockad knapp-rad och kan inte längre täckas av tabellens resize.
- Inventory-baserade fel visar LocalOutput/ErrorLocalPath i kolumnen Error-sökväg.

## 0.11.31

- Rättar dashboard-felet `The property 'Sum' cannot be found on this object`.
- Kömonitor summerar kopierade byte/tider defensivt rad för rad och fungerar även innan `queue-copy-stats.json` skapats.
- Genomsnittlig kopieringshastighet beräknas utan `Measure-Object`, för bättre PowerShell 5.1-kompatibilitet.
- Saknade runtime-JSON-filer loggas bara en gång och loggas igen när de dyker upp.

﻿# Changelog

## 0.11.30

- Felkö-vyn har tre manuella åtgärder per markerad fil: **Granska**, **Fortsätt** och **Ta bort**.
- Granska öppnar den lokala muxade MKV-filen med Windows standardspelare.
- Fortsätt tar bort felposten och återställer posten till bästa säkra QueueStage utifrån lokala filer och ffprobe (HEVC => Kodad, annan MKV => Muxad, lokal källa => Lokal källa klar).
- Ta bort rensar posten ur både felkön och hela köinventeringen samt tar bort lokala arbets-/tempfiler. UNC-originalet rörs aldrig.
- Manuella felköåtgärder skrivs till dashboardens verbose-logg.

## 0.11.29
- Rättar QueueStage-matchning efter muxning: källor som `.ts`, `.mp4`, `.avi`, `.mpg` och `.mpeg` matchas nu mot motsvarande `.mkv`-post via samma relativa basnamn.
- Felkö-vyn läser nu `Data\error-queue.json` direkt och kompletterar med QueueStage 90–92, så encoderfel syns även om en statusuppdatering missats.
- Kömonitorn får separat räknare **Klara för flytt** för QueueStage 8.
- **Kvar i kön** fortsätter räkna alla ej färdiga poster över samtliga UNC-köer.
- Dashboardens JSON-läsning görs mer tolerant mot saknade/null-fält för att undvika att hela uppdateringen bryts.

## 0.11.28 - 2026-08-10

- Flyttar **Visa statistik** till Programinställningar i Inställningar.
- Döljer Start Centers tomma PowerShell-värdfönster.
- Döljer kömonitorns tomma PowerShell-värdfönster.
- Startar det detaljerade Queue Host-konsolfönstret dolt.
- Lägger till **Visa detaljer / Dölj detaljer** i kömonitorn för att toggla Queue Host-konsolen vid behov.
- Queue Host publicerar sitt fönsterhandtag lokalt i `Data\queue-console-window.json` under körningen.
- Verbose-loggar fungerar fortsatt även när konsolfönstren är dolda.

# 0.11.27

## 0.11.27 - 2026-08-10

- Rättar ParserError i `MediaPrep-Queue-Dashboard.ps1` där bokstavliga `` `r`n `` hade hamnat i skriptkoden.
- Kömonitorn kan åter startas automatiskt från Start Center.
- När **Verbose logging** är aktivt får kömonitorn en egen logg: `Loggar\MediaPrep-Queue-Dashboard_YYYY-MM-DD_HH-mm-ss.log`.
- Dashboard-loggen registrerar start/stängning, JSON-läsfel, layoutfel och uppdateringsfel.
- Start Center skriver dessutom `Loggar\MediaPrep-Queue-Dashboard-Launcher.log` vid verbose för att felsöka själva starten av statistikprocessen.
- Behåller stöd för `.ts`, `.mp4`, `.avi`, `.mpg` och `.mpeg`.

# 0.11.26

## 0.11.26 - 2026-08-10
- Added `.mpg` and `.mpeg` as supported source formats throughout queue scanning, All-in-one, ffprobe analysis, muxing and summaries.
- Fixed regression where the queue statistics window did not always open automatically when starting the queue.
- Queue dashboard launch now uses a single quoted Windows PowerShell 5.1 argument string with `-STA`, preserving paths that contain spaces.
- Start Center now reports the dashboard process PID on successful launch and shows an explicit error if the dashboard cannot be started.

- Rättar kömonitor där kolumnerna krympte vid varje 1-sekundsuppdatering.
- DataGridView använder nu fasta kolumnbredder; endast sökväg/start-kolumnen anpassas när fönstret ändrar storlek.
- Själva dashboard-refreshen ändrar inte längre kolumnlayouten.

﻿# Changelog

## 0.11.25 - 2026-08-10
- Lade till fullständigt stöd för `.avi` som källformat tillsammans med `.ts` och `.mp4`.
- Källfiler analyseras med `ffprobe` före muxning.
- ffprobe-resultatet innehåller container, video-/audiocodec, profil, pixel format, upplösning, FPS, längd, bitrate och antal strömmar.
- Probe-data följer med skanningsposten och sparas i ködashboarden när filen går in i muxsteget.
- AVI använder samma undertext-, mux-, analys-, NVENC-, felkö- och UNC-flöde som övriga källformat.

## 0.11.22 – 2026-08-10

- Nytt separat kömonitorfönster som öppnas automatiskt när kön startas.
- Ny knapp **Visa statistik** i Startcenter för att öppna kömonitorn igen.
- Kömonitorn läser lokala `Data\queue-dashboard-inventory.json` och behöver inte läsa UNC för att visa statistik.
- `queue-dashboard-inventory.json` version 2 innehåller nu `errors` och `items`.
- Kömonitorn har vyerna **Kvar i kön**, **Felkö**, **Körningsstatistik** och **Långsamma kopieringar**.
- Felkö-vyn har knappen **Bearbeta felkön** som startar tolerant avkodning manuellt.
- Kopiering från UNC och tillbaka till UNC klockas per videofil med byte, tid och MB/s i `Data\queue-copy-stats.json`.
- Köstart/slut sparas i `Data\queue-run-current.json` med starttid, sluttid och total körtid.
- Långsamma kopieringar flaggas om de går under 30 MB/s eller under 50 % av aktuell genomsnittshastighet.

## 0.11.20 – 2026-08-10

- Flyttar köstatistiken till en egen fast GroupBox i övre högra delen av Arbetskö, ovanför kölistan.
- Statistiketiketterna skapas med 0-värden direkt och är alltid synliga i Kö-läge före inventering.
- Behåller stegvis statistikuppdatering när giltiga filer hittas samt vid köändringar.
- Förtydligar verbose STALL WARNING när både mediatid och FFmpeg CPU-tid står still.

## 0.11.19 – 2026-08-10

- Köstatistik byggs nu med fasta etiketter direkt i Översikt och hålls alltid synlig i Kö-läge.
- Statistiken uppdateras stegvis under UNC-inventering och när kön ändras.
- Verbose-loggning visar nu FFmpeg CPU-tidsdelta, arbetsminne, trådantal och hur länge mediatiden stått still.
- Verbose skriver STALL WARNING när mediatiden inte avancerat på minst 20 sekunder, tillsammans med GPU-snapshot.

## 0.11.18 – 2026-08-10

- Köstatistik ligger alltid synlig i Kö-läge och hålls längst fram i Startcentret.
- Statistik uppdateras vid köändringar och stegvis under UNC-inventering.
- Verbose logging skickas nu vidare till MediaPrep-processen.
- Verbose loggar full FFmpeg-kommandorad, FFmpeg-version, NVENC-parametrar och GPU-snapshot före/efter varje omkodning.
- GPU-snapshot innehåller bl.a. drivrutin, P-state, temperatur, GPU-/encoderbelastning och klockfrekvenser.

## 0.11.17 – 2026-08-10

- Köstatistik visas alltid i både Kö och Allt-i-ett.
- Köstatistik räknas om direkt när poster läggs till, tas bort eller flyttas.
- UNC-inventering uppdaterar statistiken för varje giltig TS/MP4-fil som hittas.
- Allt-i-ett visar även kvarvarande undertexter och antal klara MKV-filer.

﻿## 0.11.16 – 2026-08-10

- Köstatusraden visar endast om kön körs eller inte.
- Filnamn och nästa köpost tas bort från översikten.
- Antal, storlek och återflyttningsstatus visas endast i Köstatistik.

## 0.11.15 – 2026-08-10

- Starta hela kön gör nu en förkontroll av samtliga UNC-mappar innan batchen startar.
- Vid saknad UNC-åtkomst visas autentisering i den eleverade MediaPrep-sessionen och SMB-anslutningen etableras där.
- Varje UNC-kömapp verifieras för läsning, skrivning och radering med en tillfällig access-testfil.
- Köstatistiken förenklas till kvarvarande filer, bearbetade hela kön, kvarvarande storlek och klara för återflytt.
- Köstatistikens etiketter är alltid synliga i Kö-läge.
- Språkfiler version 1.3.8.

## 0.11.14 – 2026-08-10

- Ny köstatistik på Översikt: kvarvarande videofiler, kvarvarande storlek, undertexter, bearbetade filer, totalt antal och filer klara för UNC-återföring.
- Statistiken bygger en inventering av UNC-kön och uppdateras automatiskt under körningen.
- Rensningen av tomma lokala mappar omfattar nu även `Processed`.
- Startcenter 3.3.14 och språkfiler 1.3.7.

## 0.11.13 – 2026-08-08

- Rättar NVENC-progress i Windows PowerShell 5.1 genom direkt läsning av FFmpegs StandardOutput.
- Den blå progressrutan uppdateras löpande från varje komplett `progress=continue`-block.
- Progress loggas fortfarande var femte sekund utan lila konsolrader.

## 0.11.12 – 2026-08-08

- NVENC-progress läses nu löpande via `-progress pipe:1` i stället för en direkt progressfil som kunde buffras till slutet.
- Den blå progressrutan visar filnummer, filnamn, videotid, procent, kodningshastighet och uppskattad återstående tid.
- `[PROGRESS]` sparas i loggfilen var femte sekund men skrivs inte längre som lila konsolrader.
- UNC-import och UNC-återföring visar antal, totalantal, procent och aktuell fil i samma utökade progressformat.

## 0.11.11 – 2026-08-08

- Visar löpande NVENC-tid, procent, hastighet och återstående tid i den blå Write-Progress-rutan för varje fil.
- Skriver dessutom en [PROGRESS]-rad till konsol och logg var femte sekund.
- Visar kopieringsprogress när färdiga MKV-filer återförs till UNC.
- Rensar tomma undermappar i UnProcessed och Processed efter återföring och vid köslut.
- Rensningen fungerar även när en tidigare avbruten batch återupptas; mappar med kvarvarande filer lämnas orörda.

## 0.11.10 – 2026-08-08

- Rättar att en nyligen tillagd UNC-mapp försvann ur kön efter cirka 1,5 sekund.
- Kön sparas nu omedelbart till inställningsfilen när en mapp läggs till.
- Uppdateringstimern kan därför inte längre återställa listan till en äldre tom kö.

## 0.11.9 – 2026-08-08

- Rättar UNC-återföring efter återstart när `LocalVideo` är tom för filer som redan fanns i `Processed`.
- Kontrollerar tomma sökvägar innan `Test-Path` anropas.
- Lägger till maskinläsbar FFmpeg-progress under NVENC-omkodning.
- Skriver `[PROGRESS] bearbetad/total | procent | hastighet | kvar` var femte sekund till konsol och logg.

## 0.11.8 – 2026-08-08

- Gör UNC-importen återstartssäker efter avbruten muxning eller NVENC-omkodning.
- Hoppar över UNC-kopiering när motsvarande MKV redan finns i `Processed` och lokal källa saknas.
- Återanvänder en komplett fil i `UnProcessed` när storleken matchar UNC-originalet.
- Kopierar om lokala eller tillfälliga kopior som har fel storlek.
- Tvingar ny muxning när både lokal källa och motsvarande MKV finns, eftersom föregående behandling då betraktas som ofärdig.
- Sparar återstartsstatus i UNC-importmanifestet.

## 0.11.7 – 2026-08-08

- Rättar ett Windows PowerShell 5.1-fel i kontrollen av sökvägar och program.
- Generiska listor räknas och itereras nu direkt utan arraykonvertering.
- Behåller gröna bockar och röda kryss för alla mappar och programfiler.
- Uppdaterar språkfilerna till version 1.3.6.

﻿## 0.11.6 – 2026-08-08

- Visar en grön bock eller ett rött kryss för alla konfigurerade mappar och program.
- Döper om knappen till "Kontrollera sökvägar / program".
- Kontrollen omfattar installationsmapp, arbetsmappar, datamappar och externa program.
- Status uppdateras vid start, efter val av sökväg, efter sparande och vid manuell kontroll.
- Uppdaterar språkfilerna till version 1.3.5.

## 0.11.5 – 2026-08-08

- Rättar startfel där statuskontrollen användes innan den skapats under StrictMode.
- Flyttar första verktygsstatusuppdateringen till efter att statusfältet skapats.
- Gör statusfunktionen säker vid tidig initiering.

## 0.11.4 – 2026-08-08

- Flyttar rubriken "Externa verktyg" till vänsterspalten mellan mappar och verktygssökvägar.
- Tar bort den stora statusrutan för externa verktyg i högerspalten.
- Ger språkfältet och verktygsknapparna fasta bredder så att knapptexterna syns bättre.
- Justerar inställningslayouten så högerspalten får mer utrymme.

﻿# Ändringslogg

## 0.11.3 – 2026-08-08

- Återställer standardverktygssökvägar till `Tools\FFmpeg` och `Tools\MKVToolNix`.
- Delar Preferences i en kompakt vänsterpanel och en separat panel för programspråk och verktygshantering.
- Visar status och sökväg för FFmpeg, FFprobe och MKVToolNix.
- Uppdaterar språkfilerna till version 1.3.4.

# Changelog

## 0.11.3 – 2026-08-08

- File pickers for ffmpeg.exe, ffprobe.exe and mkvmerge.exe now open in the directory already configured in Preferences.
- If the configured file does not exist, the nearest existing parent directory is used.
- Language selection is kept visible in Preferences and remains available after adding the external tool manager.
- Language files updated to version 1.3.3.

# Changelog

## 0.11.3 – 2026-08-08

- Keeps a single universal launcher: `Start MediaPrep.cmd`.
- Adds `Manage-MediaPrepTools.ps1`.
- Adds tool detection, version checks and hardware encoder capability checks.
- Adds download/update support for FFmpeg and MKVToolNix from configured project distribution sources.
- Prevents queue start when required tools are missing and offers to open the tool manager.

# Changelog

## 0.11.0 — 2026-08-08

- Renamed the product to **MediaPrep MKV Toolkit**.
- Changed the default input folder from `Filmer` to `UnProcessed`.
- Preserved compatibility with existing installations that explicitly use `Filmer`.
- Kept the project PowerShell-based with no compiled MediaPrep executable.
- Added a PowerShell installer with a selectable installation folder.
- Added the complete folder structure to the distribution, including empty folders through `.gitkeep`.
- Added `LICENSE.md` for personal, non-commercial source-available use.
- Added `THIRD-PARTY-NOTICES.md` and confirmed that third-party binaries are not bundled.
- Updated language files to version 1.4.0.
