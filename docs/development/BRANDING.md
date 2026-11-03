# PRISM App Branding & UI Technical Guide

## 1. Brand Identity & Theme
PRISM (Parenteral Return-demonstration Injection Skills Monitor) utilizes a highly professional, clinical, and clean aesthetic. The application is built using Flutter and relies primarily on a customized Material 3 theme.

### Global ThemeData (Defined in `main.dart`)
* **Base Brightness**: Dark (though specific screens use a custom light theme aesthetic as seen below)
* **Seed Color**: Deep Purple (used for system fallbacks)
* **Default Scaffold Background**: `0xFF0D0D1A` (for global dark mode/splash screen)
* **Use Material 3**: `true`

---

## 2. Color Palette
The primary application interface uses a custom defined "Navy & Blue" color scheme with clean, distinct functional colors. 

### Core Brand Colors
* **Navy (Primary)**: `0xFF003366` - Used for headers, primary buttons, active tabs.
* **Navy Mid**: `0xFF004080` - Used for decorative background circles and gradients.
* **Navy Dark**: `0xFF002244` - Used for deeper backgrounds and contrast layering.
* **Accent Blue**: `0xFFA8C4E0` - Used for subtitle text, active icons, and secondary highlights.

### Background & Surface Colors
* **App Background**: `0xFFF8FAFC` - Light grayish-blue for the main app background (Scaffold).
* **Card Background**: `0xFFFFFFFF` - Pure white for content containers and list items.
* **Card Border**: `0xFFE2EAF4` - Soft blue-gray for subtle separation borders.

### Text Colors
* **Text Dark**: `0xFF1A2B3C` - Used for primary text (titles, student names).
* **Text Mid**: `0xFF4A5568` - Used for secondary text (subtitles, hints, dates).
* **Text Light**: `0xFF8A9BB0` - Used for disabled text or subtle icons.

### Status / Functional Colors
* **Green (Success/Released)**
  * Text/Icon: `0xFF1A7A4A`
  * Background: `0xFFEEF9F3`
  * Border: `0xFFA8D5B8`
* **Amber (Warning/Pending)**
  * Text/Icon: `0xFFB45309`
  * Background: `0xFFFEF9EE`
  * Border: `0xFFF6D28A`
* **Red (Error/Failed)**
  * Text/Icon: `0xFF991B1B`
  * Background: `0xFFFEF2F2`
  * Border: `0xFFFECACA`

---

## 3. Typography & Text Styles
PRISM relies on the default system fonts (San Francisco on iOS / Roboto on Android). 

### Headings (e.g., App Bar / Splash Screen)
* **App Title (PRISM)**
  * Font Size: `24.0` (Dashboard) / `32.0` (Splash Screen)
  * Font Weight: `FontWeight.w800` (Extra Bold)
  * Letter Spacing: `3.0` (Dashboard) / `6.0` (Splash Screen)
  * Color: `Colors.white`

### Subtitles & Labels
* **Header Subtitle (e.g., "INJECTION SKILLS MONITOR")**
  * Font Size: `11.0`
  * Font Weight: `FontWeight.w700` (Bold)
  * Letter Spacing: `1.5`
  * Color: `_accentBlue`
* **Card Titles (e.g., "Student Name")**
  * Font Size: `14.0` to `15.0`
  * Font Weight: `FontWeight.w600` or `FontWeight.bold`
  * Color: `_textDark`

### Body Text
* **Secondary Text (e.g., "Academic Year 2026")**
  * Font Size: `12.0` to `13.0`
  * Font Weight: `FontWeight.normal` or `FontWeight.w500`
  * Color: `_textMid`
* **Stats Numbers**
  * Font Size: `28.0`
  * Font Weight: `FontWeight.w700`

---

## 4. UI Components & Styling Rules

### Cards & Containers
* **Border Radius**: Generally `14.0` to `16.0` for large cards.
* **Borders**: Width of `1.0` or `1.5` using the `_cardBorder` color.
* **Shadows**: Soft shadows using Navy or Black with low opacity.
  * Example: `BoxShadow(color: _navy.withOpacity(0.07), blurRadius: 12, offset: Offset(0, 2))`

### Buttons & Inputs
* **Search / Input Fields**:
  * Height: `44.0`
  * Background: `0xFFF8FAFC`
  * Border Radius: `12.0`
  * Border: `Border.all(color: _cardBorder, width: 1.5)`
* **Filter Badges (Pills)**:
  * Border Radius: `20.0`
  * Padding: `horizontal: 13, vertical: 5`

### Iconography
* The app heavily utilizes **SVG Icons** with a default stroke width of `1.4` to `2.2` depending on the icon size.
* Interactive icons (like Notifications) often sit inside a circular container with an opaque white background (`Colors.white.withOpacity(0.10)`).
