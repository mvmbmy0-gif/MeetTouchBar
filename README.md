<div align="center">

# 🇺🇦 Проєкт розроблений українцем / Project developed by a Ukrainian 🇺🇦

[![Stand With Ukraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://stand-with-ukraine.pp.ua)

<p align="center">
  <img src="pictures/meet_active.png" alt="Meet TouchBar Active" width="960">
</p>

# MacBook Pro Touch Bar for Google Meet
### 📹 Instant Mic, Camera, Hand, Reactions & Tab Focus from your Touch Bar

> [!IMPORTANT]
> 🔴 **HARDWARE REQUIREMENT / ВИМОГА ДО ПРИСТРОЮ**  
> Designed for **Apple MacBook Pro (2016–2020)** with physical **Touch Bar** running macOS Big Sur, Monterey, Ventura, Sonoma, or Sequoia.  
> Працює на всіх моделях MacBook Pro з сенсорною смугою Touch Bar!

[English Documentation](#-english) | [Custom Language Guide](#-custom-language-guide) | [Українська версія](#-українська-версія) | [Як налаштувати свою мову](#-як-налаштувати-свою-мову)

---
</div>

## 📸 Screenshots / Знімки екрана

| State / Стан | Touch Bar Screenshot |
|---|---|
| **Active Meeting** (Mic On, Cam On, Hand Raised) | <img src="pictures/meet_active.png" width="900" alt="Meet Active"> |
| **Idle / Muted** (Camera On, Mic Muted) | <img src="pictures/meet_idle.png" width="900" alt="Meet Idle"> |
| **Emoji Reactions Bar** | <img src="pictures/meet_reactions.png" width="900" alt="Reactions Bar"> |

---

<a name="english"></a>
## 🇬🇧 English

### ⚡ Overview
**MeetTouchBar** brings full, native hardware control over **Google Meet** directly to your MacBook Pro Touch Bar. Mute your microphone, toggle your camera, raise your hand, send animated emoji reactions, or switch focus directly to your meeting tab — all in one tap, with **0.0% CPU usage when idle**.

### ✨ Key Features
- **🎤 Smart Microphone Indicator:** Live status tracking. Bezel turns red when unmuted.
- **📹 Camera Indicator:** Live status tracking. Bezel turns blue when camera is active.
- **✋ Hand Raised:** Instantly raise/lower hand with orange visual alert.
- **💖 Emoji Reactions Bar:** Full row of quick emoji reactions (`💖`, `👍`, `🎉`, `👏`, `😂`, `😮`, `😢`, `🤔`, `👎`).
- **↗ Focus Meeting Tab:** Instantly brings the browser tab running the meeting to the foreground.
- **🌐 Automatic Localization:** Automatically adapts to your system language (English by default, Ukrainian on Ukrainian macOS systems).
- **⚡ Ultra-low Resource Usage:** When no meetings are running, background polling stops completely (0.0% CPU, 0 network activity).

### 🚀 Installation
1. Download the latest **`MeetTouchBar-v1.0.0.zip`** from [Releases](https://github.com/mvmbmy0-gif/MeetTouchBar/releases).
2. Unzip the downloaded file.
3. Move `MeetTouchBar.app` to your Applications folder and launch it.
4. In Chrome / Brave / Edge, open `chrome://extensions`:
   - Enable **Developer mode** (top right switch).
   - Click **Load unpacked**.
   - Select the `Extension` folder included in the release.
5. Join any Google Meet call — the Touch Bar buttons appear automatically!

### 🛠️ Building From Source
```bash
git clone https://github.com/mvmbmy0-gif/MeetTouchBar.git
cd MeetTouchBar
./build.sh
```

---

<a name="custom-language-guide"></a>
## 🌍 Custom Language Guide (How to add or change language)

Adding a custom language or changing any button text takes less than 1 minute:

1. Open `main.m` in any text editor.
2. At the top of the file, locate the `kI18n` dictionary:
   ```objc
   static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *kI18n = @{
       @"en": @{
           @"mic":         @"Mic",
           @"cam":         @"Camera",
           @"hand":        @"Hand",
           @"reactions":   @"Reactions",
           @"focus":       @"To Meeting",
           @"menu_toggle": @"Show / Hide Meet Bar",
           @"menu_quit":   @"Quit MeetBar"
       },
       // Add your language here! For example, Spanish:
       @"es": @{
           @"mic":         @"Micrófono",
           @"cam":         @"Cámara",
           @"hand":        @"Mano",
           @"reactions":   @"Reacciones",
           @"focus":       @"Ir a reunión",
           @"menu_toggle": @"Mostrar / Ocultar Meet Bar",
           @"menu_quit":   @"Salir de MeetBar"
       }
   };
   ```
3. To force your language, change:
   ```objc
   #define FORCE_LANGUAGE @"es"  // or @"en", @"uk", etc.
   ```
   *(Or leave `#define FORCE_LANGUAGE nil` to auto-detect from macOS settings!)*
4. Run `./build.sh` in the terminal to recompile. Done!

---

<a name="українська-версія"></a>
## 🇺🇦 Українська версія

### ⚡ Опис проєкту
**MeetTouchBar** — це нативна утиліта для macOS, яка перетворює сенсорну панель Touch Bar на повноцінний пульт керування **Google Meet**. Вмикайте та вимикайте мікрофон чи камеру, піднімайте руку, надсилайте емодзі-реакції та миттєво повертайтеся до вкладки дзвінка в один дотик.

### ✨ Основні можливості:
- **🎤 Індикатор мікрофона:** Підсвічується червоним кольором, коли мікрофон увімкнений.
- **📹 Індикатор камери:** Підсвічується синім кольором під час трансляції відео.
- **✋ Підняття руки:** Помаранчева кнопка для швидкої реакції на уроці чи зустрічі.
- **💖 Панель реакцій:** Окреме підменю Touch Bar із великими емодзі (`💖`, `👍`, `🎉`, `👏`, `😂`, `😮`, `😢`, `🤔`, `👎`).
- **↗ Кнопка «До уроку»:** Миттєво активує вікно браузера та перемикає на вкладку з поточним дзвінком.
- **🌐 Автоматична локалізація:** Автоматично обирає українську мову на україномовних системах та англійську для решти світу.
- **⚡ Нульове навантаження на систему:** Коли дзвінок завершено або сайт Meet закритий, додаток не споживає процесор (0.0% CPU) та не розряджає батарею.

### 🚀 Встановлення та запуск:
1. Завантажте готовий архів **`MeetTouchBar-v1.0.0.zip`** зі сторінки [Релізів](https://github.com/mvmbmy0-gif/MeetTouchBar/releases).
2. Розархівуйте його.
3. Запустіть додаток `MeetTouchBar.app`.
4. У браузері (Chrome, Brave або Edge) відкрийте сторінку `chrome://extensions`:
   - Увімкніть перемикач **Режим розробника** (Developer mode).
   - Натисніть **Завантажити розпаковане розширення** (Load unpacked).
   - Оберіть папку `Extension` з архіву.
5. Увійдіть у будь-який дзвінок Google Meet — панель Touch Bar увімкнеться автоматично!

### 🛠️ Збірка проекту з вихідного коду:
```bash
git clone https://github.com/mvmbmy0-gif/MeetTouchBar.git
cd MeetTouchBar
./build.sh
```

---

<a name="як-налаштувати-свою-мову"></a>
## 🌍 Як налаштувати свою мову або змінити текст кнопок

Змінити назви кнопок або додати будь-яку іншу мову дуже просто:

1. Відкрийте файл `main.m` у будь-якому текстовому редакторі.
2. На самому початку файлу знайдіть блок `kI18n`:
   ```objc
   static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *kI18n = @{
       @"uk": @{
           @"mic":         @"Мікрофон",
           @"cam":         @"Камера",
           @"hand":        @"Рука",
           @"reactions":   @"Реакції",
           @"focus":       @"До уроку",
           @"menu_toggle": @"Показати / Сховати панель Meet",
           @"menu_quit":   @"Вийти з MeetBar"
       }
   };
   ```
3. Змініть назви на будь-які власні або додайте новий блок мови (наприклад, польську `"pl"`).
4. Щоб зафіксувати потрібну мову, вкажіть:
   ```objc
   #define FORCE_LANGUAGE @"uk"
   ```
5. Запустіть `./build.sh` у терміналі для швидкої перекомплікації.

---

### 📄 Ліцензія
Поширюється за відкритою ліцензією **MIT License**.  
Розроблено в Україні 🇺🇦.
