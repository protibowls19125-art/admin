---
name: Proti Bowls Premium
colors:
  surface: '#f9f9f7'
  surface-dim: '#dadad8'
  surface-bright: '#f9f9f7'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f4f4f2'
  surface-container: '#eeeeec'
  surface-container-high: '#e8e8e6'
  surface-container-highest: '#e2e3e1'
  on-surface: '#1a1c1b'
  on-surface-variant: '#4f4634'
  inverse-surface: '#2f3130'
  inverse-on-surface: '#f1f1ef'
  outline: '#817662'
  outline-variant: '#d3c5ae'
  surface-tint: '#795900'
  primary: '#795900'
  on-primary: '#ffffff'
  primary-container: '#d4a017'
  on-primary-container: '#503a00'
  inverse-primary: '#f6be39'
  secondary: '#5f5e5e'
  on-secondary: '#ffffff'
  secondary-container: '#e2dfde'
  on-secondary-container: '#636262'
  tertiary: '#934b19'
  on-tertiary: '#ffffff'
  tertiary-container: '#ec925a'
  on-tertiary-container: '#662c00'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdfa0'
  primary-fixed-dim: '#f6be39'
  on-primary-fixed: '#261a00'
  on-primary-fixed-variant: '#5c4300'
  secondary-fixed: '#e5e2e1'
  secondary-fixed-dim: '#c8c6c5'
  on-secondary-fixed: '#1c1b1b'
  on-secondary-fixed-variant: '#474746'
  tertiary-fixed: '#ffdbc9'
  tertiary-fixed-dim: '#ffb68c'
  on-tertiary-fixed: '#321200'
  on-tertiary-fixed-variant: '#753401'
  background: '#f9f9f7'
  on-background: '#1a1c1b'
  surface-variant: '#e2e3e1'
typography:
  headline-xl:
    fontFamily: Playfair Display
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
  headline-lg:
    fontFamily: Playfair Display
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-md:
    fontFamily: Playfair Display
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '700'
    lineHeight: 16px
    letterSpacing: 0.1em
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
  stack-sm: 4px
  stack-md: 12px
  stack-lg: 24px
---

## Brand & Style

The design system is rooted in a "Premium Gastronomy" aesthetic, balancing the warmth of artisanal food with the precision of a high-end concierge service. It evokes feelings of health, indulgence, and exclusivity.

The visual style is **Corporate / Modern** with **Minimalist** sensibilities, utilizing expansive whitespace to let high-quality food photography act as the primary texture. The personality is sophisticated yet approachable, using high-contrast serif typography to signal quality and modern sans-serifs to ensure functional clarity. To elevate the experience for premium features like membership cards, subtle **Glassmorphism** and soft metallic gradients are introduced.

## Colors

The palette is inspired by natural ingredients and luxury materials:
- **Primary (Gold):** A rich, muted gold used for highlights, rewards, and premium call-to-actions.
- **Secondary (Charcoal):** A deep, near-black used for primary text and high-contrast surfaces (like "Active" states).
- **Tertiary (Earthy Umber):** A warm brown used sparingly for price tags or organic accents.
- **Neutral:** A "Bone White" foundation that feels warmer and more organic than pure digital white.

For the premium membership experience, use a linear gradient from `#D4A017` to `#F3D078` to simulate a brushed gold finish.

## Typography

This design system uses a high-contrast typographic pairing:
- **Playfair Display** handles all editorial titles and product names, providing a literary, upscale feel. It should be used with tight tracking to maintain its "fashion-magazine" elegance.
- **Plus Jakarta Sans** provides a friendly, modern counter-balance for UI labels, body descriptions, and navigation. 
- All caps are reserved for **label-sm** (e.g., "FEATURED CREATION") to create a structured information hierarchy without overwhelming the page.

## Layout & Spacing

The layout follows a **Fluid Grid** model for mobile and a **Fixed Grid** (max-width 1200px) for desktop. 

- **Vertical Rhythm:** Built on an 8px baseline. Content blocks (like product cards) should be separated by `stack-lg`.
- **Margins:** A consistent 20px "Safe Area" on mobile devices ensures content doesn't feel cramped.
- **Reflow:** On mobile, content is primarily single-column. On tablet, product grids transition to 2-columns; on desktop, 3 or 4 columns depending on the screen width.

## Elevation & Depth

The design system uses **Tonal Layers** rather than heavy shadows to signify depth. 
- **Level 0 (Base):** Neutral Bone White background.
- **Level 1 (Cards):** Pure White surface with a very soft, high-diffusion shadow (Opacity 4%, Blur 20px) or a subtle 1px border in a slightly darker neutral tone.
- **Premium Tier:** Uses **Glassmorphism**. For membership overlays or card details, use a backdrop-blur of 12px with a 60% white opacity fill and a 1px "inner glow" border to simulate physical glass.

## Shapes

The shape language is "Softly Geometric."
- **Standard UI (Inputs, Buttons):** 0.5rem (8px) radius.
- **Containers (Cards, Hero Images):** 1.5rem (24px) radius to create a friendly, modern appearance.
- **Chips/Pills:** Fully rounded (pill-shaped) to distinguish them from actionable buttons.

## Components

- **Buttons:** Primary buttons use the Secondary (Charcoal) color with white text for maximum "pop." Premium buttons use the Gold gradient.
- **Membership Card:** A signature component featuring a gold-to-light-gold gradient, white serif text, and a frosted-glass overlay for the member's QR code or ID.
- **Search Bar:** A light neutral fill (`#F0F0EE`) with 8px rounding and a subtle icon, keeping the interface clean and focused on the imagery.
- **Category Chips:** Use a light grey background for inactive states and the Secondary Charcoal for the active state to provide clear visual feedback.
- **Navigation:** A bottom-docked bar on mobile using high-quality iconography and the Primary Gold for the active indicator.
- **Price Labels:** Displayed in the Tertiary Umber or Primary Gold, utilizing the serif font for a "boutique" feel.