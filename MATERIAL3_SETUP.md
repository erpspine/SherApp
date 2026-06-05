# Sher ERP - Material 3 Implementation ✓

## Overview

The Sher ERP Flutter app is now fully configured with **Material Design 3** (Material You), providing a modern, adaptive design system with proper color schemes, typography, and component styling.

## Material 3 Features Implemented

### 1. **Enhanced ColorScheme**

- Complete Material 3 color palette with all required roles:
  - Primary: Sher Gold (`#C9A961`)
  - Secondary: Sher Navy (`#1F3A4A`)
  - Tertiary: Sher Red (`#E63946`)
  - Surface, Outline, Error colors with proper contrast
  - Container and "onContainer" colors for Material 3 components
  - Inverse colors for Material 3 surfaces

### 2. **Material 3 Typography**

- **TextTheme** fully configured with Material 3 scales:
  - Display Large/Medium/Small
  - Headline Large/Medium/Small
  - Title Large/Medium/Small
  - Body Large/Medium/Small
  - Label Large/Medium/Small
- All using **Inter** font for brand consistency

### 3. **Material 3 Components**

#### Buttons

```dart
// Elevated Button (Primary action)
ElevatedButton(
  onPressed: () {},
  child: const Text('Sign In'),
)

// Filled Button (Alternative primary)
FilledButton(
  onPressed: () {},
  child: const Text('Save'),
)

// Outlined Button (Secondary action)
OutlinedButton(
  onPressed: () {},
  child: const Text('Cancel'),
)

// Text Button (Tertiary action)
TextButton(
  onPressed: () {},
  child: const Text('Learn More'),
)
```

#### Input Fields

- Material 3 text fields with proper focus states
- Filled backgrounds with outline borders
- Gold focus border on interaction
- Color-coded error states

#### Cards

- Material 3 elevation (0 for flat design)
- Proper border radius (12dp)
- Surface variant colors
- Surface tint color support

### 4. **Dark Theme with Material You**

The app uses a dark theme optimized for the Sher brand:

- Background: `#0F172A` (Dark blue-gray)
- Surface: `#1E293B` (Card background)
- Proper contrast ratios for accessibility

### 5. **AppBar**

- Material 3 centered/left-aligned titles
- No shadow elevation (flat design)
- Proper color inheritance from ColorScheme

### 6. **Additional Material 3 Themes**

- Drawer with rounded corners
- Bottom sheets with Material 3 styling
- Dialogs with proper shape and colors
- Chips with updated styling
- Progress indicators with brand color

## How to Use Material 3 in Screens

### Basic Setup

```dart
import 'package:flutter/material.dart';
import '../config/theme.dart';

class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Screen'),
      ),
      body: Column(
        children: [
          // Use theme colors
          Text(
            'Hello',
            style: Theme.of(context).textTheme.headlineLarge,
          ),

          // Use color scheme
          Container(
            color: Theme.of(context).colorScheme.primary,
          ),

          // Material 3 buttons
          ElevatedButton(
            onPressed: () {},
            child: const Text('Primary Action'),
          ),

          OutlinedButton(
            onPressed: () {},
            child: const Text('Secondary Action'),
          ),
        ],
      ),
    );
  }
}
```

## Material 3 Color Roles

### Primary Colors

```dart
colorScheme.primary          // Sher Gold - Main actions
colorScheme.onPrimary        // White - Text on gold
colorScheme.primaryContainer // Dark variant for backgrounds
```

### Secondary Colors

```dart
colorScheme.secondary        // Sher Navy - Supporting elements
colorScheme.onSecondary      // White - Text on navy
```

### Tertiary Colors

```dart
colorScheme.tertiary         // Sher Red - Accents/alerts
colorScheme.onTertiary       // White - Text on red
```

### Surface Colors

```dart
colorScheme.background       // Page background
colorScheme.surface          // Card/container background
colorScheme.surfaceVariant   // Alternative surface
colorScheme.onSurface        // Text on surface
```

### Error & Status

```dart
colorScheme.error            // Red for errors
colorScheme.outline          // Borders and dividers
colorScheme.outlineVariant   // Secondary borders
```

## Theme Access in Widgets

### Access TextTheme

```dart
Theme.of(context).textTheme.headlineLarge
Theme.of(context).textTheme.bodyMedium
Theme.of(context).textTheme.labelSmall
```

### Access ColorScheme

```dart
Theme.of(context).colorScheme.primary
Theme.of(context).colorScheme.surface
Theme.of(context).colorScheme.error
```

### Via SherTheme Constants

```dart
import '../config/theme.dart';

SherTheme.sherGold              // #C9A961
SherTheme.sherNavy              // #1F3A4A
SherTheme.sherRed               // #E63946
SherTheme.heading1              // 28px, w800
SherTheme.bodyLarge             // 16px, w500
SherTheme.sherGradient          // Sher brand gradient
```

## Button Styling Best Practices

### Primary Action (Most Emphasis)

```dart
ElevatedButton(
  onPressed: () {},
  child: const Text('Save Changes'),
)
// Uses: Primary color (Gold) background, white text
```

### Secondary Action (Medium Emphasis)

```dart
FilledButton(
  onPressed: () {},
  child: const Text('Continue'),
)
// Uses: Primary color background
```

### Tertiary Action (Least Emphasis)

```dart
OutlinedButton(
  onPressed: () {},
  child: const Text('Cancel'),
)
// Uses: Outline with primary color border
```

### Minimal Action

```dart
TextButton(
  onPressed: () {},
  child: const Text('Forgot Password?'),
)
// Uses: Text color only, no background
```

## Input Field Styling

Material 3 text fields automatically get:

- Filled background with dark theme
- Gold border on focus
- Proper label positioning
- Rounded corners (10dp)
- Icon color management

```dart
TextField(
  decoration: InputDecoration(
    labelText: 'Email Address',
    prefixIcon: const Icon(Icons.email_outlined),
  ),
)
// Theme handles the rest!
```

## Accessibility

Material 3 implementation includes:

- ✅ WCAG AA contrast ratios
- ✅ Proper color differentiation (not just color coding)
- ✅ Semantic HTML/Material semantics
- ✅ Touch target sizing (minimum 48dp)

## Files Modified

- ✅ `lib/config/theme.dart` - Complete Material 3 theme
- ✅ `lib/main.dart` - Updated to use SherTheme.darkTheme
- ✅ `lib/screens/login_screen.dart` - Material 3 components
- ✅ `pubspec.yaml` - Material 3 enabled

## Material 3 Principles Applied

1. **Color** - Dynamic, branded colors from Sher design
2. **Typography** - Hierarchical text scales with Inter font
3. **Shape** - Consistent rounded corners (12-16dp)
4. **Motion** - Built-in Material animations
5. **Elevation** - Flat design with strategic shadows
6. **Component Theming** - All widgets respect theme

## Next Steps

To apply Material 3 to other screens:

1. **Use Theme Data** instead of hardcoding colors:

   ```dart
   // ❌ Don't do this
   Container(color: Color(0xFFD4A843))

   // ✅ Do this instead
   Container(color: Theme.of(context).colorScheme.primary)
   ```

2. **Use TextTheme** for consistent typography:

   ```dart
   // ❌ Don't do this
   Text('Title', style: TextStyle(fontSize: 20, color: Colors.white))

   // ✅ Do this
   Text('Title', style: Theme.of(context).textTheme.headlineMedium)
   ```

3. **Use Material 3 Components**:
   - `ElevatedButton` instead of `RaisedButton`
   - `FilledButton` for primary actions
   - `OutlinedButton` for secondary actions
   - `TextButton` for minimal actions

---

**Status**: 🎨 Material 3 fully implemented! All components follow Material Design 3 guidelines.
