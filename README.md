# Image Viewer

Nativní prohlížeč obrázků pro macOS 13 a novější, napsaný ve Swiftu a AppKitu. Bez externích závislostí a bez importu fotek do knihovny.

## Sestavení a spuštění

Potřebujete Xcode nebo Command Line Tools se Swiftem 6.

Pro sestavení spusťte v Terminálu:

```sh
cd /Users/roman.makudera/projekty/mac-image-viewer
zsh scripts/build-app.sh
```

Skript vytvoří release build `dist/Image Viewer.app`, přibalí novou ikonu a aplikaci lokálně podepíše. Hotovou aplikaci spustíte ze stejné složky:

```sh
open "dist/Image Viewer.app"
```

Po novém sestavení nejprve ukončete běžící Image Viewer přes ⌘Q a spusťte jej znovu. Pokud používáte kopii v `/Applications` nebo `~/Applications`, nahraďte ji novou aplikací ze složky `dist`.

Ikona aplikace je v `Resources/AppIcon.png`; původní zadání a způsob generování jsou v `Resources/AppIcon-prompt.txt`. Hlavní build skript při změně PNG automaticky spustí `scripts/build-icon.sh`, který vytvoří `Resources/AppIcon.icns` s běžnými i Retina velikostmi. Samostatné přegenerování ikony lze spustit příkazem `zsh scripts/build-icon.sh`; pro její přibalení pak znovu spusťte hlavní build.

Aplikaci můžete přesunout do `/Applications` nebo `~/Applications`. Ve Finderu potom použijte **Otevřít v aplikaci → Jiná…** a vyberte Image Viewer. Výchozí aplikaci lze změnit v **Informace → Otevřít v aplikaci → Změnit vše…**. Build má lokální ad hoc podpis; distribuce na další počítače by vyžadovala samostatně vyřešit podpis a notarizaci.

## Výchozí prohlížeč a vývoj bez kopírování

V horním menu **Image Viewer → Nastavit jako výchozí prohlížeč obrázků…** vyberte formáty a potvrďte **Nastavit jako výchozí**. K dispozici jsou JPEG, PNG, HEIC, HEIF, TIFF, BMP, WebP a GIF, které aplikace registruje ve Finderu. Změny se provádějí jednotlivě pomocí systémového API macOS; pokud systém požádá o souhlas, potvrďte jej. Závěrečný dialog ukáže úspěšně nastavené formáty i případné chyby. Zrušení výběrového dialogu nic nemění.

Nastavuje se právě spuštěná `.app`. Je proto vhodné nejprve aplikaci umístit na stálé místo, případně ji spouštět přes odkaz na `dist`. Nové buildy ve stejné složce obvykle nevyžadují opakovat nastavení. Po přesunutí aplikace můžete příkaz zopakovat.

Pro vývoj lze místo kopírování každého buildu vytvořit symlink:

```sh
mkdir -p "$HOME/Applications"
```

Pokud v `~/Applications` ještě neexistuje položka `Image Viewer Dev.app`, vytvořte ji:

```sh
ln -s "/Users/roman.makudera/projekty/mac-image-viewer/dist/Image Viewer.app" \
      "$HOME/Applications/Image Viewer Dev.app"
```

Spouštějte tento odkaz; každý nový build se projeví po ukončení a opětovném spuštění aplikace. Projekt musí zůstat na stejné cestě. Odkaz nevytvářejte přes existující položku. Alternativou je alias ve Finderu vytvořený přetažením aplikace se stisknutými ⌥⌘. Pokud máte zároveň starou samostatnou kopii v `/Applications`, zkontrolujte, že spouštíte požadovanou verzi.

## Ukládání nastavení

Aplikace používá systémové předvolby macOS (`UserDefaults`), bez samostatného konfiguračního souboru v projektu. Pamatuje si checkbox **Přizpůsobit oknu**, viditelnost panelu informací/EXIF, velikost náhledů galerie a interval prezentace. Nastavení je společné pro buildy se stejným identifikátorem aplikace `cz.romanmakudera.imageviewer`; macOS je spravuje v `~/Library/Preferences/cz.romanmakudera.imageviewer.plist`.

Výchozí přizpůsobení je zapnuté. Ukládá se pouze jeho výslovná změna checkboxem nebo volbou v menu. Dočasný zoom touchpadem, tlačítky nebo zobrazení 100 % uložené nastavení nemění, takže další fotka nepřevezme nechtěně vypnuté přizpůsobení. Starý příznak `fitToScreen` z raných buildů se ignoruje. Nastavení lze přečíst příkazem:

```sh
defaults read cz.romanmakudera.imageviewer
```

## Ovládání

| Akce | Ovládání |
|---|---|
| Otevřít | ⌘O, Finder nebo přetažení do okna |
| Předchozí / další | ← / →, ↑ / ↓ nebo kolečko; mezerník pro další |
| Galerie složky | Tlačítko Galerie ve spodní liště nebo ⌘G |
| Celá obrazovka | F nebo ⌃⌘F |
| Opustit celou obrazovku | Esc |
| Informace a EXIF | I nebo ⌘I |
| Kopírovat EXIF a metadata jako JSON | Tlačítko v EXIF panelu nebo ⌘⇧C |
| Otočit doleva / doprava | Úpravy nebo ⌘L / ⌘R |
| Převrátit vodorovně / svisle | Úpravy → Převrátit… |
| Výřez | ⌘K, tažením vybrat oblast, Enter potvrdit, Esc zrušit |
| Změna šířky a výšky | Úpravy → Změnit rozměry… |
| Vrátit poslední úpravu | ⌘Z |
| Přiblížit / oddálit | + / −, tlačítka v liště, gesto sevření/roztažení nebo ⌘ + posun dvěma prsty nahoru/dolů |
| Posun zvětšeného obrázku | Tažení myší |
| Skutečná velikost | ⌘0 |
| Přizpůsobit oknu | Checkbox v liště nebo ⌘9 |
| Uložit aktuální podobu jako… | ⌘S nebo Soubor → Uložit jako… |
| Porovnat s originálem | Podržet B, uvolnit pro návrat |
| Přesunout do koše | ⌘⌫ nebo kontextové menu obrázku |
| Vrátit poslední obrázek z koše | ⌘⇧Z nebo Soubor → Vrátit poslední obrázek z koše |
| Zobrazit ve Finderu | ⌘⇧R nebo kontextové menu |
| Kopírovat cestu | ⌘⌥C nebo kontextové menu |
| Spustit prezentaci | ⌘P, volba intervalu 1–60 s |
| Zastavit prezentaci | Esc nebo ⌘. |
| Hromadné úpravy a převod | Galerie → Výběr více → Operace… |
| Označit všechny fotky | Galerie → Vybrat vše nebo ⌘A |
| Ukončit | ⌘Q |

Obrázky ve stejné složce se řadí přirozeně podle názvu (`foto2` před `foto10`); skryté soubory, podadresáře a ostatní formáty se vynechají. Procházení je cyklické: vlevo z první fotky přejdete na poslední, vpravo z poslední na první. Totéž platí pro tlačítka předchozí/další a kolečko. Chybné obrázky zobrazí chybu a lze pokračovat šipkou. Panel informací obsahuje základní údaje a všechna dostupná metadata včetně EXIF, pokud je soubor obsahuje. Text lze označit a kopírovat.

Formáty pro procházení určuje systémový ImageIO. Aplikace je ve Finderu registrována pro JPEG, PNG, HEIC/HEIF, TIFF, BMP, WebP a GIF. Z vícesnímkových souborů se zobrazí první snímek, bez animace. Aplikace respektuje EXIF orientaci. Zapnuté **Přizpůsobit oknu** vyplní dostupnou plochu při zachování poměru stran, včetně zvětšení malých obrázků. Přizpůsobení reaguje na změnu velikosti okna i fullscreen. Při prvním spuštění je zapnuté; ruční změna checkboxu se ukládá do systémových předvoleb a obnoví se při dalším spuštění i přepnutí obrázku. Ruční zoom checkbox vypne; vypnutí checkboxu nebo ⌘0 nastaví 100 %. Při přepnutí na jinou fotku se ruční zoom a posun zruší a obnoví se uložená volba přizpůsobení. Je-li zapnutá, celý obrázek se vejde do obrazové plochy nad stavovou lištou. Při ručním zoomu se kreslení ořízne na tuto plochu a nikdy nepřekrývá lištu ani panel informací.

## EXIF jako JSON

Panel informací (I / ⌘I) obsahuje tlačítko **Kopírovat EXIF jako JSON**. Stejný příkaz je v menu **Úpravy** a má zkratku **⌘⇧C**. Do schránky uloží formátovaný JSON všech dostupných metadat původního souboru, včetně sekcí `{Exif}`, `{TIFF}` a `{GPS}`, pokud jsou přítomné. Původní názvy klíčů z ImageIO zůstávají zachované; čísla a seznamy zůstávají čísly a seznamy. Binární hodnoty se zapisují jako objekt s `encoding: "base64"` a `data`, datumové objekty jako ISO 8601. Bez EXIF se zkopírují zbývající metadata. Neuložené úpravy obrázku tato původní metadata nemění. Při načítání nebo chybě obrázku je kopírování nedostupné.

## Galerie

Tlačítko **Galerie** ve spodní liště (nebo **Zobrazení → Galerie**, ⌘G) zobrazí všechny obrázky aktuální složky v posuvné mřížce, zleva doprava a shora dolů ve stejném přirozeném pořadí jako při procházení detailu. Náhledy se vejdou celé do buněk se zachovaným poměrem stran a orientací podle EXIF; pod nimi je název souboru. Aktuální fotka je zvýrazněná. V běžném režimu se jediným kliknutím, včetně kliknutí na aktuální fotku, galerie zavře a otevře se detail vybraného obrázku. Pro výběr více souborů zapněte **Výběr více**, případně použijte ⌘/⇧ při klikání. Posuvník ve spodní liště mění velikost náhledů a jeho nastavení se pamatuje. Tlačítko **Operace…** pracuje s aktuálním výběrem; ⌘A označí všechny obrázky. Esc nebo opětovné stisknutí Galerie vrátí předchozí detail. Šipky v galerii vybírají položku, Enter ji otevře. Šipky vlevo/vpravo přecházejí cyklicky mezi první a poslední položkou.

Náhledy se načítají na pozadí při zobrazení položek. Používají paměťovou cache do 64 MB a diskovou cache v `~/Library/Caches/cz.romanmakudera.imageviewer/Thumbnails-v1` s průběžným promazáváním směrem k limitu 256 MB. Disková cache funguje i po restartu aplikace a změna velikosti nebo času úpravy původního souboru ji zneplatní. Galerie ukazuje soubory na disku; neuložené úpravy zůstávají uchované pro jejich detail. Poškozený obrázek dostane zástupnou ikonu a zůstane možné otevřít jeho detail.

## Úpravy

**Úpravy → Změnit rozměry…** otevře dialog se šířkou a výškou v pixelech. Zapnuté **Zachovat poměr stran** automaticky dopočítá druhý rozměr při změně kteréhokoli pole; vypnutím lze šířku a výšku nastavit nezávisle. Hodnoty musí být celá čísla 1–30 000 px s celkovou plochou nejvýše 100 megapixelů. Změna rozměrů se provádí převzorkováním, zachovává průhlednost, funguje se Zpět a promítá se do exportu. Rozlišení náhledu odpovídá oknu a Retina displeji, nejvýše 6000 px; ukládání používá skutečné zadané rozměry.

Stavová lišta zobrazuje **aktuální šířku × výšku v pixelech** po provedených úpravách a **typ otevřeného souboru**, např. `1920 × 1080 px · JPEG`. Rozměry reagují na změnu velikosti, rotaci, výřez, Zpět i obnovení originálu; zoom je neovlivňuje. Typ se určuje podle obsahu, nikoli jen přípony. Při uložení kopie zůstává otevřený původní soubor, takže lišta dál uvádí jeho typ.

Menu **Úpravy** obsahuje rotace o 90°, vodorovné a svislé převrácení a obdélníkový výřez. Výřez funguje i při zoomu a posunu. Vyberte oblast tažením a stiskněte Enter, případně použijte **Úpravy → Potvrdit výřez**. Esc výběr zruší. Příkaz **Zpět – poslední úprava** vrátí poslední krok; **Obnovit původní obrázek** zruší všechny úpravy aktuální fotky.

Úpravy se zachovávají při procházení aktuálně otevřené složky. Při otevření jiného souboru, zavření okna nebo ukončení aplikace se při neuložených úpravách zobrazí nabídka **Uložit vše…**, **Zahodit změny**, **Zrušit**. Uložení všech změn otevře dialog hromadných operací s volbou cílové složky; při zrušení nebo chybě exportu se původní akce neprovede. EXIF panel nadále zobrazuje metadata původního souboru. Pro rychlé zobrazení se nejprve použije menší náhled nebo vložený náhled z fotografie. Následně se doostří podle velikosti okna a Retina displeje. Při ručním zoomu se bez vymazání zobrazené fotky načte detail do 6000 px na delší straně. Zoom nad toto rozlišení zvětšuje náhled; export nadále pracuje s plným originálem.

## Uložení

**Soubor → Uložit jako… (⌘S)** otevře systémový dialog s výběrem místa, názvu a formátu. V nabídce **Formát** jsou PNG, JPEG, TIFF a HEIC podle dostupnosti systémového encoderu. Přípona se přizpůsobuje zvolenému formátu. Výchozí název končí `-upraveno`, takže se obvykle uloží nová kopie. Nahrazení existujícího souboru potvrzuje systémový dialog.

Ukládání znovu načte originál v plném rozlišení a použije potvrzené rotace, převrácení, výřezy a změny rozměrů. Zoom, posun a velikost okna výstup nemění. Rozpracovaný výřez je nejprve nutné potvrdit nebo zrušit. PNG a TIFF uchovávají průhlednost; JPEG ji nahradí bílým pozadím. Kvalitu JPEG/HEIC lze nastavit posuvníkem (10–100 %, výchozí 90 %). Volba **Zachovat EXIF a další metadata** uchová podporované EXIF/TIFF/IPTC údaje; orientace a rozměry se přepočítají podle výsledku. Zaškrtnuté **Vynechat GPS souřadnice** odstraní GPS sekci. Obě volby jsou při otevření dialogu zapnuté. Soubor se nejprve celý zakóduje v paměti a poté atomicky zapíše; chyba kódování nepoškodí existující cíl. Po nahrazení právě prohlíženého originálu se znovu načte uložená verze, aby se úpravy nepoužily dvakrát.

**⌘ + posun dvěma prsty** mění plynule zoom bez přepínání souborů; funguje také s kolečkem myši. Bez ⌘ zůstává posun určený k procházení složky. Setrvačnost zoomovacího gesta nepřepne na další obrázek ani po uvolnění ⌘.

První obrázek se načítá souběžně s procházením složky. Rychlý náhled, jeho doostření a přednačítání sousedních fotek mají oddělené fronty; pomalé přednačítání neblokuje přepnutí šipkou. Přednačítá se nejprve další fotka a poté předchozí. Cache detailů má limit 192 MB; menší náhledy podle velikosti okna do ní uloží více fotek. Opožděné výsledky po rychlém přepínání se zahodí a dostupné obrázky z cache se zobrazí okamžitě. Aplikace není sandboxovaná, aby při otevření obrázku mohla číst i ostatní obrázky ve složce; systémová oprávnění macOS pro chráněné složky stále platí. Pokud složku nelze vypsat, zobrazí se samotný otevřený soubor.

## Porovnání, koš a prezentace

V detailu podržte **B** pro dočasné zobrazení původního obrázku. Po uvolnění se vrátí upravená podoba; historie úprav se nemění.

**Soubor → Přesunout do koše… (⌘⌫)** po potvrzení přesune aktuální soubor do systémového koše. Nejde o trvalé smazání. **Soubor → Vrátit poslední obrázek z koše (⌘⇧Z)** jej vrátí na původní místo včetně jeho neuložených úprav. Obnovení nepřepisuje soubor, který mezitím vznikl na stejné cestě. Historie přesunů je dostupná během tohoto spuštění aplikace; po ukončení lze soubory obnovit standardně z koše ve Finderu.

**Zobrazení → Spustit prezentaci… (⌘P)** nabídne interval 1–60 sekund a přepne do fullscreenu. Fotky se cyklicky střídají; poškozené soubory neblokují pokračování. Prezentaci ukončíte přes Esc nebo **Zastavit prezentaci (⌘.)**. Otevření jiného souboru, galerie, úprava nebo export ji zastaví. Pokud jste už před prezentací byli ve fullscreenu, příkaz Zastavit tento režim zachová.

Pravé tlačítko nad obrázkem nabízí **Zobrazit ve Finderu**, **Kopírovat cestu** a **Přesunout do koše…**. V galerii je kontextové menu pro označené soubory; kopírování více cest je oddělí novými řádky.

## Dávkové operace

V galerii zapněte **Výběr více** a označte obrázky. **Vybrat vše** ve spodní liště nebo **⌘A** označí celou složku. **Operace…** ve spodní liště, kontextové menu **Operace s výběrem…** nebo **Soubor → Operace s vybranými…** otevře společný dialog:

- **Změnit rozměry:** šířka a výška v pixelech. Se zachováním poměru stran se obrázky vejdou do zadaného obdélníku; bez něj se použijí oba rozměry nezávisle. Výchozí **Pouze zmenšit** zabrání zvětšení menších fotek.
- **Rotace:** bez otočení, doleva/doprava o 90° nebo o 180°. Použije se na všechny vybrané obrázky před změnou rozměrů.
- **Formát:** PNG, JPEG, TIFF nebo HEIC. Volba **Původní** zachová JPEG/PNG/TIFF/HEIC podle obsahu jednotlivých souborů; ostatní typy uloží jako PNG.
- **Uložit do:** přímo do aktuální složky, do složky vybrané systémovým dialogem nebo do nové podsložky v aktuálním adresáři.

Lze kombinovat rotaci, rozměry, převod formátu i nastavení kvality a metadat. Použijí se také dosavadní neuložené úpravy jednotlivých fotek. Výsledkem jsou **kopie s příponou `-upraveno`**, původní soubory se nepřepisují. Existující názvy dostanou číselnou příponu, například `foto-upraveno-2.jpg`. Uložení do zadané složky zapisuje přímo do ní, bez další povinné podsložky. Po uložení do aktuálního adresáře galerie načte nové soubory a zachová původní výběr.

Průběh lze zastavit po aktuálním obrázku; již uložené výstupy zůstanou zachované. Chyba jednoho souboru neblokuje ostatní a zobrazí se v závěrečném přehledu. Operace mění výstupní kopie, nikoli zdrojové soubory ani velikost náhledů.

## Testy

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox --cache-path "$PWD/.build/cache"
```
