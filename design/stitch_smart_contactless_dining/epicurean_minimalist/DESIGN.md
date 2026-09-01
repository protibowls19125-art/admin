---
name: Epicurean Minimalist
colors:
  surface: '#fbf9f9'
  surface-dim: '#dbdad9'
  surface-bright: '#fbf9f9'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f5f3f3'
  surface-container: '#efeded'
  surface-container-high: '#e9e8e7'
  surface-container-highest: '#e4e2e2'
  on-surface: '#1b1c1c'
  on-surface-variant: '#444748'
  inverse-surface: '#303031'
  inverse-on-surface: '#f2f0f0'
  outline: '#747878'
  outline-variant: '#c4c7c7'
  surface-tint: '#5f5e5e'
  primary: '#0a0a0a'
  on-primary: '#ffffff'
  primary-container: '#212121'
  on-primary-container: '#898888'
  inverse-primary: '#c8c6c5'
  secondary: '#9f402d'
  on-secondary: '#ffffff'
  secondary-container: '#fd876f'
  on-secondary-container: '#732010'
  tertiary: '#080a09'
  on-tertiary: '#ffffff'
  tertiary-container: '#202120'
  on-tertiary-container: '#888887'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e5e2e1'
  primary-fixed-dim: '#c8c6c5'
  on-primary-fixed: '#1b1c1c'
  on-primary-fixed-variant: '#474746'
  secondary-fixed: '#ffdad3'
  secondary-fixed-dim: '#ffb4a5'
  on-secondary-fixed: '#3e0500'
  on-secondary-fixed-variant: '#802918'
  tertiary-fixed: '#e3e2e0'
  tertiary-fixed-dim: '#c7c6c5'
  on-tertiary-fixed: '#1a1c1b'
  on-tertiary-fixed-variant: '#464746'
  background: '#fbf9f9'
  on-background: '#1b1c1c'
  surface-variant: '#e4e2e2'
typography:
  headline-lg:
    fontFamily: Playfair Display
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Playfair Display
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  headline-md:
    fontFamily: Playfair Display
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: 0.05em
  price-display:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '500'
    lineHeight: '1'
    letterSpacing: -0.01em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  container-padding: 20px
  gutter: 16px
  stack-sm: 12px
  stack-md: 24px
  stack-lg: 48px
---

## Brand & Style

The design system is centered on a "Modern Bistro" philosophy—sophisticated, clean, and intentionally appetizing. It targets a discerning audience that values culinary excellence and seamless technology. The aesthetic response should be one of "effortless luxury"; the interface stays out of the way of the food photography while providing a premium, tactile experience.

The design style is a blend of **Minimalism** and **Modern Corporate**, utilizing heavy whitespace to frame high-quality imagery. The mood is calm and professional, ensuring that the transition from a physical table setting to a digital interface feels cohesive and elevated.

## Colors

The palette is anchored by **Rich Charcoal** (#212121) for primary text and grounding elements, providing high contrast against the **Soft Off-White** (#F9F8F6) background. This off-white base reduces glare and feels more "organic" than pure white, mimicking high-end menu paper.

The accent color is **Terracotta** (#E2725B), used exclusively for call-to-action buttons and interactive highlights. This warm, earth-toned hue is psychologically proven to stimulate appetite while standing out clearly against the neutral backdrop. Secondary text uses a mid-tone grey (#707070) to maintain a clear visual hierarchy without distracting from the main headlines.

## Typography

This design system employs a classic serif/sans-serif pairing to communicate both heritage and modernity. **Playfair Display** is used for headlines and dish names, lending an editorial, "chef-curated" feel to the menu. 

**Inter** is the functional workhorse for all UI elements, descriptions, and pricing. It provides exceptional readability on mobile devices. For price displays, a medium weight is used to ensure clarity. Labels for dietary restrictions (e.g., VEGAN, GLUTEN-FREE) should use the `label-md` style with uppercase tracking to differentiate them from body descriptions.

## Layout & Spacing

The layout follows a **mobile-first fluid grid**. On mobile, the system uses a single-column layout with 20px side margins to ensure content feels breathable and premium.

On larger screens (tablet/desktop), the layout expands into a 12-column grid. Components like menu cards should be grouped in flexible containers that reflow from 1 column (mobile) to 2 columns (tablet) to 3 or 4 columns (desktop). Spacing follows an 8px base unit, with a preference for generous vertical "stack" spacing to separate courses and sections clearly.

## Elevation & Depth

Depth is communicated through **Tonal Layers** and **Ambient Shadows**. The background is the lowest layer (`#F9F8F6`). Interactive cards (like individual menu items) sit on a pure white surface with a very soft, diffused shadow (0px 4px 20px rgba(0, 0, 0, 0.04)).

This subtle elevation creates a "paper-on-table" effect. Modals and floating action buttons (like the "View Cart" bar) use a slightly more pronounced shadow (0px 10px 30px rgba(0, 0, 0, 0.08)) to indicate high priority and immediate interaction. Avoid heavy borders; use light dividers (#EDEDED) sparingly to separate list items.

## Shapes

The design system uses a **Rounded** language (0.5rem / 8px) to soften the professional charcoal tones and make the UI feel approachable. 

- **Cards and Containers:** 8px (base)
- **Primary Buttons:** 12px (rounded-lg) for a more inviting, tactile feel.
- **Images:** 16px (rounded-xl) to create a "framed" portrait look for food photography.
- **Selection Chips:** Pill-shaped (fully rounded) to indicate quick, toggleable interactions.

## Components

### Buttons
- **Primary:** Terracotta background with white text. High-padding (16px 24px), bold sans-serif.
- **Secondary:** Charcoal outline with charcoal text. Used for "Add to Cart" or "Customize."

### Menu Cards
Images should take the full width of the card at the top, with a 3:2 aspect ratio. Typography sits below with generous padding. Prices should be right-aligned or positioned clearly at the bottom right in the `price-display` style.

### Inputs & Selectors
- **Search:** Subtle grey background with a 1px border that darkens on focus.
- **Quantity Selector:** A minimalist horizontal component with '+' and '-' icons and the number centered.

### Chips & Tags
Used for dietary tags (GF, V, DF). Small, pill-shaped, with a light grey background and dark grey text to remain secondary to the main content.

### Floating Cart Bar
A persistent bar at the bottom of the screen on mobile. It should use a subtle backdrop blur (glassmorphism) over the white container to show the menu scrolling underneath, providing a sense of depth and context.