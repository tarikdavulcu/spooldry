# -*- coding: utf-8 -*-
"""App Store metadata for SpoolDry in EN, DE, FR, ES, AR, JA (single source of truth).
Used by tools/build_store_assets.py (fastlane metadata + screenshots) and docs/ASO.md.
Apple limits: name 30, subtitle 30, promotional text 170, keywords 100, description 4000, what's new 4000.
"""

LOCALES = {
    "en": "en-US", "de": "de-DE", "fr": "fr-FR", "es": "es-ES", "ar": "ar-SA", "ja": "ja",
}

ASO = {
"en": {
    "name": "SpoolDry: Filament Dryer",
    "subtitle": "ESP32 BLE drying & humidity",
    "hook": "Know exactly when your filament is dry. SpoolDry connects your ESP32 filament dryer to your iPhone and tracks temperature, humidity and every bake.",
    "promo": "Dry PLA to PA-CF with confidence: live temperature and humidity, a Live Activity timer and engineering polymer profiles. 3 bakes free, then one Lifetime unlock.",
    "keywords": "3d printing,humidity,esp32,bluetooth,nylon,petg,pla,abs,asa,tpu,dry box,hygrometer,spool,moisture",
    "headlines": ["Track Your Filament", "Temperature + Humidity", "Engineering Polymer Profiles", "ESP32 BLE Connected",
                  "Live Activity Drying Timer", "Know When Drying Is Complete", "Works Completely Offline", "One-Time Lifetime Purchase"],
    "whatsnew": "First release of SpoolDry:\n• Direct Bluetooth control of your ESP32 filament dryer\n• Live temperature and humidity\n• Live Activity and Dynamic Island drying timer\n• Widgets for your Home Screen\n• Typical drying guidance for PLA, PETG, ABS, ASA, TPU, PA, PC, PVA, BVOH, PEEK, PEI, PPS and fiber-filled grades\n• Offline history and statistics",
    "description": """SpoolDry turns your ESP32-based filament dryer into a connected drying station. Your iPhone talks directly to the dryer over Bluetooth Low Energy: no account, no cloud, no internet required.

KNOW WHEN YOUR FILAMENT IS DRY
Wet filament strings, pops, foams and prints weak parts. SpoolDry shows the chamber temperature and relative humidity live, so you see the moisture leave the spool instead of guessing.

BUILT FOR ENGINEERING POLYMERS
Start from typical drying guidance for PLA, PETG, ABS, ASA, TPU, PA (nylon), PC, PVA, BVOH, PEEK, PEI/ULTEM, PPS and carbon- or glass-fiber grades. Every value is labelled as typical starting guidance with links to the manufacturer pages it was summarised from. Create your own profiles for the exact brands you print.

LIVE ACTIVITY & DYNAMIC ISLAND
Follow preheating, drying and cooldown from the Lock Screen. The timer only runs once the dryer reports that it reached the target temperature: no fake progress.

SAFETY STAYS ON THE DRYER
The ESP32 firmware runs the session on its own and enforces temperature limits, sensor checks, fan monitoring and a watchdog. If your iPhone leaves the room, drying continues safely and SpoolDry catches up when you return.

HISTORY & STATISTICS
Every session is saved on your iPhone with start and end humidity, average temperature and a chart. See total drying hours, average humidity reduction and your most-used material.

MULTIPLE DRYERS
Name your dryers (SpoolDry #1, #2 …) and switch between them.

OPEN HARDWARE
The firmware, BLE protocol, wiring diagram and bill of materials are published on the SpoolDry website. Hardware is a DIY project and is not certified; follow the safety guide.

PRICING
Your first 3 drying sessions are free. SpoolDry Lifetime is a one-time purchase that unlocks unlimited sessions and multiple dryers. No subscription.

Try the built-in demo dryer if you have not built your hardware yet.""",
},
"de": {
    "name": "SpoolDry: Filamenttrockner",
    "subtitle": "ESP32-BLE Trocknung & Feuchte",
    "hook": "Wisse genau, wann dein Filament trocken ist. SpoolDry verbindet deinen ESP32-Filamenttrockner mit dem iPhone und erfasst Temperatur, Feuchte und jede Trocknung.",
    "promo": "Von PLA bis PA-CF sicher trocknen: Temperatur und Feuchte live, Timer als Live-Aktivität und Profile für technische Kunststoffe. 3 Trocknungen gratis, dann Einmalkauf.",
    "keywords": "3d druck,luftfeuchtigkeit,feuchte,esp32,bluetooth,nylon,petg,pla,abs,trockenbox,hygrometer,spule",
    "headlines": ["Dein Filament im Blick", "Temperatur + Feuchte", "Profile für technische Kunststoffe", "ESP32 per BLE verbunden",
                  "Trocknungs-Timer als Live-Aktivität", "Wissen, wann es trocken ist", "Funktioniert komplett offline", "Einmalkauf statt Abo"],
    "whatsnew": "Erste Version von SpoolDry:\n• Direkte Bluetooth-Steuerung deines ESP32-Filamenttrockners\n• Temperatur und Feuchte live\n• Trocknungs-Timer als Live-Aktivität und in der Dynamic Island\n• Widgets für den Home-Bildschirm\n• Typische Trocknungswerte für PLA, PETG, ABS, ASA, TPU, PA, PC, PVA, BVOH, PEEK, PEI, PPS und faserverstärkte Typen\n• Offline-Verlauf und Statistiken",
    "description": """SpoolDry macht deinen ESP32-Filamenttrockner zur vernetzten Trocknungsstation. Dein iPhone spricht direkt per Bluetooth Low Energy mit dem Trockner: kein Konto, keine Cloud, kein Internet nötig.

WISSEN, WANN DEIN FILAMENT TROCKEN IST
Feuchtes Filament zieht Fäden, knackt, schäumt und ergibt schwache Bauteile. SpoolDry zeigt Kammertemperatur und relative Feuchte live, damit du siehst, wie die Feuchtigkeit die Spule verlässt, statt zu raten.

FÜR TECHNISCHE KUNSTSTOFFE GEMACHT
Starte mit typischen Trocknungswerten für PLA, PETG, ABS, ASA, TPU, PA (Nylon), PC, PVA, BVOH, PEEK, PEI/ULTEM, PPS sowie kohle- und glasfasergefüllte Typen. Jeder Wert ist als typischer Startwert gekennzeichnet und verlinkt die Herstellerseiten, aus denen er zusammengefasst wurde. Lege eigene Profile für deine Marken an.

LIVE-AKTIVITÄT & DYNAMIC ISLAND
Verfolge Vorheizen, Trocknen und Abkühlen auf dem Sperrbildschirm. Der Timer läuft erst, wenn der Trockner das Erreichen der Zieltemperatur meldet: kein geschönter Fortschritt.

SICHERHEIT BLEIBT IM TROCKNER
Die ESP32-Firmware führt die Trocknung selbstständig aus und überwacht Temperaturgrenzen, Sensoren, Lüfter und einen Watchdog. Verlässt dein iPhone den Raum, läuft die Trocknung sicher weiter und SpoolDry holt später auf.

VERLAUF & STATISTIKEN
Jede Trocknung wird auf deinem iPhone gespeichert, mit Start- und Endfeuchte, Durchschnittstemperatur und Diagramm. Sieh Trocknungsstunden, durchschnittliche Feuchte-Reduktion und dein meistgenutztes Material.

MEHRERE TROCKNER
Benenne deine Trockner (SpoolDry #1, #2 …) und wechsle zwischen ihnen.

OFFENE HARDWARE
Firmware, BLE-Protokoll, Schaltplan und Stückliste findest du auf der SpoolDry-Website. Die Hardware ist ein DIY-Projekt und nicht zertifiziert; beachte die Sicherheitshinweise.

PREIS
Deine ersten 3 Trocknungen sind kostenlos. SpoolDry Lifetime ist ein Einmalkauf für unbegrenzte Trocknungen und mehrere Trockner. Kein Abo.

Noch keine Hardware gebaut? Probiere den integrierten Demo-Trockner.""",
},
"fr": {
    "name": "SpoolDry : Sécheur filament",
    "subtitle": "Séchage ESP32 BLE & humidité",
    "hook": "Sachez exactement quand votre filament est sec. SpoolDry relie votre sécheur de filament ESP32 à l'iPhone et suit température, humidité et chaque séchage.",
    "promo": "Séchez du PLA au PA-CF : température et humidité en direct, minuteur en activité en direct et profils de polymères techniques. 3 séchages offerts, puis achat unique.",
    "keywords": "impression 3d,humidité,esp32,bluetooth,nylon,petg,pla,abs,boîte sèche,hygromètre,bobine,séchage",
    "headlines": ["Suivez votre filament", "Température + humidité", "Profils de polymères techniques", "ESP32 connecté en BLE",
                  "Minuteur en activité en direct", "Sachez quand c'est sec", "Fonctionne entièrement hors ligne", "Achat unique à vie"],
    "whatsnew": "Première version de SpoolDry :\n• Contrôle Bluetooth direct de votre sécheur de filament ESP32\n• Température et humidité en direct\n• Minuteur en activité en direct et Dynamic Island\n• Widgets pour l'écran d'accueil\n• Repères de séchage pour PLA, PETG, ABS, ASA, TPU, PA, PC, PVA, BVOH, PEEK, PEI, PPS et grades chargés en fibres\n• Historique et statistiques hors ligne",
    "description": """SpoolDry transforme votre sécheur de filament ESP32 en station de séchage connectée. L'iPhone communique directement avec le sécheur en Bluetooth Low Energy : sans compte, sans cloud, sans internet.

SACHEZ QUAND VOTRE FILAMENT EST SEC
Un filament humide file, crépite, mousse et donne des pièces fragiles. SpoolDry affiche en direct la température de la chambre et l'humidité relative : vous voyez l'humidité quitter la bobine au lieu de deviner.

CONÇU POUR LES POLYMÈRES TECHNIQUES
Partez de repères de séchage typiques pour PLA, PETG, ABS, ASA, TPU, PA (nylon), PC, PVA, BVOH, PEEK, PEI/ULTEM, PPS et grades chargés en fibres de carbone ou de verre. Chaque valeur est indiquée comme repère de départ typique, avec les liens vers les pages des fabricants résumées. Créez vos propres profils pour vos marques.

ACTIVITÉ EN DIRECT & DYNAMIC ISLAND
Suivez préchauffage, séchage et refroidissement depuis l'écran verrouillé. Le minuteur ne démarre que lorsque le sécheur signale avoir atteint la température cible : aucune progression fictive.

LA SÉCURITÉ RESTE DANS LE SÉCHEUR
Le firmware ESP32 gère le séchage de façon autonome : limites de température, contrôle des capteurs, surveillance du ventilateur et watchdog. Si l'iPhone s'éloigne, le séchage continue en sécurité et SpoolDry se met à jour au retour.

HISTORIQUE & STATISTIQUES
Chaque séance est enregistrée sur l'iPhone avec humidité initiale et finale, température moyenne et graphique. Consultez les heures de séchage, la réduction moyenne d'humidité et votre matériau favori.

PLUSIEURS SÉCHEURS
Nommez vos sécheurs (SpoolDry #1, #2 …) et passez de l'un à l'autre.

MATÉRIEL OUVERT
Firmware, protocole BLE, schéma de câblage et nomenclature sont publiés sur le site SpoolDry. Le matériel est un projet DIY non certifié ; suivez le guide de sécurité.

TARIF
Vos 3 premiers séchages sont gratuits. SpoolDry à vie est un achat unique qui débloque les séchages illimités et plusieurs sécheurs. Sans abonnement.

Pas encore de matériel ? Essayez le sécheur de démo intégré.""",
},
"es": {
    "name": "SpoolDry: Secador filamento",
    "subtitle": "Secado ESP32 BLE y humedad",
    "hook": "Sabe exactamente cuándo tu filamento está seco. SpoolDry conecta tu secador de filamento ESP32 con el iPhone y registra temperatura, humedad y cada secado.",
    "promo": "Seca de PLA a PA-CF con confianza: temperatura y humedad en vivo, temporizador en Actividad en vivo y perfiles técnicos. 3 secados gratis y luego compra única.",
    "keywords": "impresión 3d,humedad,esp32,bluetooth,nailon,petg,pla,abs,caja seca,higrómetro,bobina,secado",
    "headlines": ["Controla tu filamento", "Temperatura + humedad", "Perfiles de polímeros técnicos", "ESP32 conectado por BLE",
                  "Temporizador en Actividad en vivo", "Sabe cuándo está seco", "Funciona totalmente sin conexión", "Compra única de por vida"],
    "whatsnew": "Primera versión de SpoolDry:\n• Control directo por Bluetooth de tu secador de filamento ESP32\n• Temperatura y humedad en vivo\n• Temporizador en Actividad en vivo y Dynamic Island\n• Widgets para la pantalla de inicio\n• Pautas de secado para PLA, PETG, ABS, ASA, TPU, PA, PC, PVA, BVOH, PEEK, PEI, PPS y grados con fibra\n• Historial y estadísticas sin conexión",
    "description": """SpoolDry convierte tu secador de filamento ESP32 en una estación de secado conectada. Tu iPhone habla directamente con el secador por Bluetooth Low Energy: sin cuenta, sin nube y sin internet.

SABE CUÁNDO TU FILAMENTO ESTÁ SECO
El filamento húmedo hace hilos, chasquidos, espuma y piezas débiles. SpoolDry muestra en vivo la temperatura de la cámara y la humedad relativa, para que veas cómo sale la humedad en lugar de adivinar.

PENSADO PARA POLÍMEROS TÉCNICOS
Parte de pautas de secado típicas para PLA, PETG, ABS, ASA, TPU, PA (nailon), PC, PVA, BVOH, PEEK, PEI/ULTEM, PPS y grados con fibra de carbono o vidrio. Cada valor se marca como pauta inicial típica, con enlaces a las páginas de los fabricantes resumidas. Crea perfiles propios para tus marcas.

ACTIVIDAD EN VIVO Y DYNAMIC ISLAND
Sigue el precalentamiento, el secado y el enfriamiento desde la pantalla bloqueada. El temporizador solo empieza cuando el secador informa que alcanzó la temperatura objetivo: sin progreso ficticio.

LA SEGURIDAD ESTÁ EN EL SECADOR
El firmware ESP32 gestiona el secado por sí mismo con límites de temperatura, control de sensores, supervisión del ventilador y watchdog. Si el iPhone sale de la habitación, el secado continúa de forma segura y SpoolDry se actualiza al volver.

HISTORIAL Y ESTADÍSTICAS
Cada sesión se guarda en tu iPhone con humedad inicial y final, temperatura media y gráfico. Consulta horas de secado, reducción media de humedad y tu material más usado.

VARIOS SECADORES
Nombra tus secadores (SpoolDry #1, #2 …) y cambia entre ellos.

HARDWARE ABIERTO
El firmware, el protocolo BLE, el esquema de cableado y la lista de materiales están publicados en la web de SpoolDry. El hardware es un proyecto DIY no certificado; sigue la guía de seguridad.

PRECIO
Tus 3 primeros secados son gratis. SpoolDry de por vida es una compra única que desbloquea secados ilimitados y varios secadores. Sin suscripción.

¿Aún no tienes hardware? Prueba el secador de demostración integrado.""",
},
"ar": {
    "name": "SpoolDry: مجفف الخيوط",
    "subtitle": "تجفيف ESP32 عبر BLE والرطوبة",
    "hook": "اعرف بدقة متى يجف خيط الطباعة. يربط SpoolDry مجفف الخيوط المبني على ESP32 بجهاز iPhone ويتابع الحرارة والرطوبة وكل جلسة تجفيف.",
    "promo": "جفّف من PLA حتى PA-CF بثقة: حرارة ورطوبة مباشرة، ومؤقت في النشاط المباشر، وملفات للبوليمرات الهندسية. 3 جلسات مجانًا ثم شراء لمرة واحدة.",
    "keywords": "طباعة ثلاثية الأبعاد,رطوبة,تجفيف,esp32,بلوتوث,نايلون,petg,pla,abs,فلامنت,بكرة",
    "headlines": ["تابع خيوط الطباعة", "الحرارة + الرطوبة", "ملفات البوليمرات الهندسية", "ESP32 متصل عبر BLE",
                  "مؤقت التجفيف في النشاط المباشر", "اعرف متى يكتمل التجفيف", "يعمل دون اتصال بالكامل", "شراء لمرة واحدة مدى الحياة"],
    "whatsnew": "الإصدار الأول من SpoolDry:\n• تحكم مباشر عبر البلوتوث في مجفف الخيوط ESP32\n• حرارة ورطوبة مباشرة\n• مؤقت التجفيف في النشاط المباشر والجزيرة الديناميكية\n• أدوات للشاشة الرئيسية\n• إرشادات تجفيف نموذجية لـ PLA وPETG وABS وASA وTPU وPA وPC وPVA وBVOH وPEEK وPEI وPPS والأنواع المدعمة بالألياف\n• سجل وإحصاءات دون اتصال",
    "description": """يحوّل SpoolDry مجفف الخيوط المبني على ESP32 إلى محطة تجفيف متصلة. يتواصل الـ iPhone مباشرة مع المجفف عبر Bluetooth منخفض الطاقة: بلا حساب ولا سحابة ولا حاجة إلى الإنترنت.

اعرف متى يجف خيطك
الخيط الرطب يُخرج خيوطًا وفرقعات ورغوة وقطعًا ضعيفة. يعرض SpoolDry حرارة الحجرة والرطوبة النسبية مباشرة، فترى الرطوبة تغادر البكرة بدل التخمين.

مصمم للبوليمرات الهندسية
ابدأ من إرشادات تجفيف نموذجية لـ PLA وPETG وABS وASA وTPU وPA (النايلون) وPC وPVA وBVOH وPEEK وPEI/ULTEM وPPS والأنواع المدعمة بألياف الكربون أو الزجاج. كل قيمة مُعلَّمة بوصفها إرشادًا نموذجيًا للبداية مع روابط لصفحات المصنّعين التي لُخّصت منها. أنشئ ملفاتك الخاصة لعلاماتك التجارية.

النشاط المباشر والجزيرة الديناميكية
تابع التسخين المسبق والتجفيف والتبريد من شاشة القفل. لا يبدأ المؤقت إلا عندما يُبلغ المجفف ببلوغ الحرارة المستهدفة: بلا تقدم وهمي.

السلامة داخل المجفف
يدير البرنامج الثابت لـ ESP32 الجلسة بنفسه مع حدود للحرارة وفحص للحساسات ومراقبة للمروحة ومؤقت حراسة. إذا غادر الـ iPhone الغرفة يستمر التجفيف بأمان ويتزامن SpoolDry عند عودتك.

السجل والإحصاءات
تُحفظ كل جلسة على الـ iPhone مع الرطوبة الأولية والنهائية ومتوسط الحرارة ومخطط بياني. اطّلع على ساعات التجفيف ومتوسط انخفاض الرطوبة والمادة الأكثر استخدامًا.

عدة مجففات
سمِّ مجففاتك (SpoolDry #1 و#2 …) وتنقّل بينها.

عتاد مفتوح
البرنامج الثابت وبروتوكول BLE ومخطط التوصيل وقائمة المكونات منشورة على موقع SpoolDry. العتاد مشروع صنع ذاتي وغير معتمد؛ اتبع دليل السلامة.

السعر
أول 3 جلسات تجفيف مجانية. SpoolDry مدى الحياة شراء لمرة واحدة يفتح جلسات غير محدودة وعدة مجففات. بدون اشتراك.

لم تبنِ العتاد بعد؟ جرّب المجفف التجريبي المدمج.""",
},
"ja": {
    "name": "SpoolDry: フィラメント乾燥",
    "subtitle": "ESP32 BLE乾燥と湿度管理",
    "hook": "フィラメントの乾燥完了がひと目でわかる。SpoolDryはESP32フィラメントドライヤーとiPhoneをつなぎ、温度・湿度・すべての乾燥を記録します。",
    "promo": "PLAからPA-CFまで安心して乾燥。温度と湿度をリアルタイム表示、ライブアクティビティのタイマー、エンジニアリングポリマーのプロファイル。3回無料、その後は買い切り。",
    "keywords": "3dプリンター,乾燥機,ドライヤー,湿度,esp32,bluetooth,ナイロン,petg,pla,abs,ドライボックス,湿度計,スプール",
    "headlines": ["フィラメントを管理", "温度＋湿度", "エンジニアリングポリマー対応", "ESP32とBLEで接続",
                  "ライブアクティビティで乾燥タイマー", "乾燥完了がわかる", "完全オフラインで動作", "買い切りの永久ライセンス"],
    "whatsnew": "SpoolDry 初回リリース：\n• ESP32フィラメントドライヤーをBluetoothで直接操作\n• 温度と湿度をリアルタイム表示\n• ライブアクティビティとDynamic Islandの乾燥タイマー\n• ホーム画面ウィジェット\n• PLA、PETG、ABS、ASA、TPU、PA、PC、PVA、BVOH、PEEK、PEI、PPS、繊維入りグレードの乾燥目安\n• オフラインの履歴と統計",
    "description": """SpoolDryは、ESP32ベースのフィラメントドライヤーをつながる乾燥ステーションに変えます。iPhoneはBluetooth Low Energyでドライヤーと直接通信。アカウントもクラウドもインターネットも不要です。

乾燥完了がわかる
湿ったフィラメントは糸引き、破裂音、発泡、強度低下の原因になります。SpoolDryは庫内温度と相対湿度をリアルタイムで表示し、スプールから水分が抜けていく様子を確認できます。

エンジニアリングポリマーに対応
PLA、PETG、ABS、ASA、TPU、PA（ナイロン）、PC、PVA、BVOH、PEEK、PEI/ULTEM、PPS、カーボン・ガラス繊維入りグレードの一般的な乾燥目安から始められます。各値は「一般的な初期目安」と明記し、要約元のメーカーページへのリンク付き。使用するブランドごとに独自のプロファイルも作成できます。

ライブアクティビティとDynamic Island
予熱・乾燥・冷却をロック画面で確認。ドライヤーが目標温度到達を報告してから初めてタイマーが動きます。見せかけの進捗はありません。

安全はドライヤー側で
ESP32ファームウェアがセッションを自律的に実行し、温度上限、センサーチェック、ファン監視、ウォッチドッグを適用します。iPhoneが離れても乾燥は安全に続き、戻ったときにSpoolDryが同期します。

履歴と統計
各セッションは開始・終了時の湿度、平均温度、グラフとともにiPhoneに保存。合計乾燥時間、平均湿度低下、最も使った素材を確認できます。

複数のドライヤー
ドライヤーに名前を付け（SpoolDry #1、#2 …）、切り替えて使えます。

オープンハードウェア
ファームウェア、BLEプロトコル、配線図、部品表はSpoolDryのウェブサイトで公開しています。ハードウェアは認証されていないDIYプロジェクトです。安全ガイドに従ってください。

料金
最初の3回の乾燥は無料。SpoolDry 永久ライセンスは無制限の乾燥と複数ドライヤーを解除する買い切りです。サブスクはありません。

ハードウェアがまだない方は、内蔵のデモドライヤーをお試しください。""",
},
}

LIMITS = {"name": 30, "subtitle": 30, "promo": 170, "keywords": 100, "description": 4000, "whatsnew": 4000}


def validate():
    problems = []
    for lang, d in ASO.items():
        for field, limit in LIMITS.items():
            n = len(d[field])
            if n > limit:
                problems.append(f"{lang}.{field}: {n} > {limit}")
        if len(d["headlines"]) != 8:
            problems.append(f"{lang}: needs 8 headlines")
        kws = d["keywords"].split(",")
        if any(k != k.strip() for k in kws):
            problems.append(f"{lang}.keywords: no spaces around commas")
        if len(set(kws)) != len(kws):
            problems.append(f"{lang}.keywords: duplicates")
    return problems


if __name__ == "__main__":
    p = validate()
    for lang, d in ASO.items():
        print(lang, {f: len(d[f]) for f in LIMITS})
    print("\n".join(p) if p else "ASO metadata within Apple limits")
