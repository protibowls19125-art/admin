# M·PROTI Dining User

Customer-facing app for M·PROTI Contactless Dining system.

## Features

- **Browse Menu**: View menu items by category
- **Add to Cart**: Build and customize your order
- **Place Order**: Complete order with table selection
- **Track Orders**: View order status and history

## Setup

1. Copy `.env.example` to `.env` and fill in your values:
   ```
   CLERK_PUBLISHABLE_KEY=your_key
   SUPABASE_URL=your_url
   SUPABASE_ANON_KEY=your_key
   ```

2. Install dependencies:
   ```
   flutter pub get
   ```

3. Run the app:
   ```
   flutter run
   ```

## Architecture

- **Pages**: Customer-facing UI screens
- **Providers**: State management using Provider
- **Services**: Supabase integration
- **Models**: Data models (MenuItem, Order, CartItem, etc.)

## Database

See parent project Supabase setup instructions.
