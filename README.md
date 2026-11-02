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

Aplikace používá systémové předvolby macOS (`UserDefaults`), bez samostatného konfiguračního souboru v projektu. Pamatuje si checkbox **Přizpůsobit oknu** a viditelnost panelu informací/EXIF. Nastavení je společné pro buildy se stejným identifikátorem aplikace `cz.romanmakudera.imageviewer`; macOS je spravuje v `~/Library/Preferences/cz.romanmakudera.imageviewer.plist`.

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
| Ukončit | ⌘Q |

Obrázky ve stejné složce se řadí přirozeně podle názvu (`foto2` před `foto10`); skryté soubory, podadresáře a ostatní formáty se vynechají. Procházení je cyklické: vlevo z první fotky přejdete na poslední, vpravo z poslední na první. Totéž platí pro tlačítka předchozí/další a kolečko. Chybné obrázky zobrazí chybu a lze pokračovat šipkou. Panel informací obsahuje základní údaje a všechna dostupná metadata včetně EXIF, pokud je soubor obsahuje. Text lze označit a kopírovat.

Formáty pro procházení určuje systémový ImageIO. Aplikace je ve Finderu registrována pro JPEG, PNG, HEIC/HEIF, TIFF, BMP, WebP a GIF. Z vícesnímkových souborů se zobrazí první snímek, bez animace. Aplikace respektuje EXIF orientaci. Zapnuté **Přizpůsobit oknu** vyplní dostupnou plochu při zachování poměru stran, včetně zvětšení malých obrázků. Přizpůsobení reaguje na změnu velikosti okna i fullscreen. Při prvním spuštění je zapnuté; ruční změna checkboxu se ukládá do systémových předvoleb a obnoví se při dalším spuštění i přepnutí obrázku. Ruční zoom checkbox vypne; vypnutí checkboxu nebo ⌘0 nastaví 100 %. Při přepnutí na jinou fotku se ruční zoom a posun zruší a obnoví se uložená volba přizpůsobení. Je-li zapnutá, celý obrázek se vejde do obrazové plochy nad stavovou lištou. Při ručním zoomu se kreslení ořízne na tuto plochu a nikdy nepřekrývá lištu ani panel informací.

## EXIF jako JSON

Panel informací (I / ⌘I) obsahuje tlačítko **Kopírovat EXIF jako JSON**. Stejný příkaz je v menu **Úpravy** a má zkratku **⌘⇧C**. Do schránky uloží formátovaný JSON všech dostupných metadat původního souboru, včetně sekcí `{Exif}`, `{TIFF}` a `{GPS}`, pokud jsou přítomné. Původní názvy klíčů z ImageIO zůstávají zachované; čísla a seznamy zůstávají čísly a seznamy. Binární hodnoty se zapisují jako objekt s `encoding: "base64"` a `data`, datumové objekty jako ISO 8601. Bez EXIF se zkopírují zbývající metadata. Neuložené úpravy obrázku tato původní metadata nemění. Při načítání nebo chybě obrázku je kopírování nedostupné.

## Galerie

Tlačítko **Galerie** ve spodní liště (nebo **Zobrazení → Galerie**, ⌘G) zobrazí všechny obrázky aktuální složky v posuvné mřížce, zleva doprava a shora dolů ve stejném přirozeném pořadí jako při procházení detailu. Náhledy se vejdou celé do buněk se zachovaným poměrem stran a orientací podle EXIF; pod nimi je název souboru. Aktuální fotka je zvýrazněná. Jediným kliknutím, včetně kliknutí na aktuální fotku, se galerie zavře a otevře se detail vybraného obrázku. Esc nebo opětovné stisknutí Galerie vrátí předchozí detail. Šipky v galerii vybírají položku, Enter ji otevře. Šipky vlevo/vpravo přecházejí cyklicky mezi první a poslední položkou.

Náhledy se načítají na pozadí při zobrazení položek a používají vlastní cache do 64 MB. Galerie ukazuje soubory na disku; neuložené úpravy zůstávají uchované pro jejich detail. Poškozený obrázek dostane zástupnou ikonu a zůstane možné otevřít jeho detail.

## Úpravy

**Úpravy → Změnit rozměry…** otevře dialog se šířkou a výškou v pixelech. Zapnuté **Zachovat poměr stran** automaticky dopočítá druhý rozměr při změně kteréhokoli pole; vypnutím lze šířku a výšku nastavit nezávisle. Hodnoty musí být celá čísla 1–30 000 px s celkovou plochou nejvýše 100 megapixelů. Změna rozměrů se provádí převzorkováním, zachovává průhlednost, funguje se Zpět a promítá se do exportu. Náhled zůstává omezený na 6000 px, ale ukládání používá skutečné zadané rozměry.

Stavová lišta zobrazuje **aktuální šířku × výšku v pixelech** po provedených úpravách a **typ otevřeného souboru**, např. `1920 × 1080 px · JPEG`. Rozměry reagují na změnu velikosti, rotaci, výřez, Zpět i obnovení originálu; zoom je neovlivňuje. Typ se určuje podle obsahu, nikoli jen přípony. Při uložení kopie zůstává otevřený původní soubor, takže lišta dál uvádí jeho typ.

Menu **Úpravy** obsahuje rotace o 90°, vodorovné a svislé převrácení a obdélníkový výřez. Výřez funguje i při zoomu a posunu. Vyberte oblast tažením a stiskněte Enter, případně použijte **Úpravy → Potvrdit výřez**. Esc výběr zruší. Příkaz **Zpět – poslední úprava** vrátí poslední krok; **Obnovit původní obrázek** zruší všechny úpravy aktuální fotky.

Úpravy se zachovávají při procházení aktuálně otevřené složky. Nové otevření souboru nebo ukončení aplikace zahodí neuložené úpravy. EXIF panel nadále zobrazuje metadata původního souboru. Pro úsporu paměti se dekóduje náhled do 6000 px na delší straně; zoom nad toto rozlišení zvětšuje náhled a neodhalí další detail originálu.

## Uložení

**Soubor → Uložit jako… (⌘S)** otevře systémový dialog s výběrem místa, názvu a formátu. V nabídce **Formát** jsou PNG, JPEG, TIFF a HEIC podle dostupnosti systémového encoderu. Přípona se přizpůsobuje zvolenému formátu. Výchozí název končí `-upraveno`, takže se obvykle uloží nová kopie. Nahrazení existujícího souboru potvrzuje systémový dialog.

Ukládání znovu načte originál v plném rozlišení a použije potvrzené rotace, převrácení a výřezy. Zoom, posun a velikost okna výstup nemění. Rozpracovaný výřez je nejprve nutné potvrdit nebo zrušit. PNG a TIFF uchovávají průhlednost; JPEG ji nahradí bílým pozadím a používá kvalitu 90 %. Export aktuálně nepřenáší původní EXIF metadata. Soubor se nejprve celý zakóduje v paměti a poté atomicky zapíše; chyba kódování nepoškodí existující cíl. Po nahrazení právě prohlíženého originálu se znovu načte uložená verze, aby se úpravy nepoužily dvakrát.

**⌘ + posun dvěma prsty** mění plynule zoom bez přepínání souborů; funguje také s kolečkem myši. Bez ⌘ zůstává posun určený k procházení složky. Setrvačnost zoomovacího gesta nepřepne na další obrázek ani po uvolnění ⌘.

Načítání a přednačtení sousedních obrázků běží na pozadí, cache má limit 192 MB. Aplikace není sandboxovaná, aby při otevření obrázku mohla číst i ostatní obrázky ve složce; systémová oprávnění macOS pro chráněné složky stále platí. Pokud složku nelze vypsat, zobrazí se samotný otevřený soubor.

## Testy

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox --cache-path "$PWD/.build/cache"
```
