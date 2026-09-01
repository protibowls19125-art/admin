# M·PROTI Dining — Complete Setup Guide

This project contains a separated admin and user app for the M·PROTI Contactless Dining system.

## 📁 Project Structure

```
Billing/
├── admin/                    # Admin Flutter App
│   ├── lib/
│   │   ├── pages/           # Admin pages (dashboard, menu, orders, analytics)
│   │   ├── providers/       # Admin state management
│   │   ├── services/        # Supabase service
│   │   ├── models/          # Data models
│   │   └── theme/           # UI theme
│   ├── pubspec.yaml
│   ├── .env.example
│   └── README.md
│
├── user/                     # Customer Flutter App
│   ├── lib/
│   │   ├── pages/           # Customer pages (home, menu, orders, etc.)
│   │   ├── providers/       # Customer state management
│   │   ├── services/        # Supabase service
│   │   ├── models/          # Data models
│   │   └── theme/           # UI theme
│   ├── pubspec.yaml
│   ├── .env.example
│   └── README.md
│
├── SUPABASE_SETUP.sql       # Database schema & RLS policies
└── SETUP_GUIDE.md           # This file
```

## 🚀 Getting Started

### Step 1: Supabase Setup

1. **Create Supabase Project**
   - Go to [supabase.com](https://supabase.com)
   - Create new project
   - Get your `SUPABASE_URL` and `SUPABASE_ANON_KEY` from project settings

2. **Setup Database**
   - Open Supabase SQL Editor
   - Copy entire contents of `SUPABASE_SETUP.sql`
   - Paste into SQL Editor and run

3. **Create Storage Bucket** (for menu images)
   - Go to Storage section
   - Create bucket named `menu-images`
   - Set to public

4. **Setup Clerk Auth**
   - Create account at [clerk.com](https://clerk.com)
   - Create new application
   - Get your `CLERK_PUBLISHABLE_KEY`
   - Configure OAuth providers (Google recommended)

### Step 2: Admin App Setup

```bash
cd admin

# Copy environment file
cp .env.example .env

# Edit .env with your Supabase and Clerk credentials
# CLERK_PUBLISHABLE_KEY=your_key
# SUPABASE_URL=your_url
# SUPABASE_ANON_KEY=your_key

# Install dependencies
flutter pub get

# Run admin app
flutter run
```

### Step 3: User App Setup

```bash
cd user

# Copy environment file
cp .env.example .env

# Edit .env with same credentials as admin app
# CLERK_PUBLISHABLE_KEY=your_key
# SUPABASE_URL=your_url
# SUPABASE_ANON_KEY=your_key

# Install dependencies
flutter pub get

# Run user app
flutter run
```

## 📱 Admin App Features

- **Dashboard**: Real-time order overview
- **Menu Manager**: Add, edit, delete menu items; toggle availability
- **Orders**: View all orders with status tracking
- **Analytics**: Revenue and popular items analytics
- **Authentication**: Secure admin login with Clerk

## 📱 Customer App Features

- **Menu Browsing**: Browse menu items by category
- **Shopping Cart**: Add items, manage quantities
- **Order Placement**: Place orders with table selection
- **Order History**: View past and current orders
- **Authentication**: Clerk-based customer authentication

## 🔐 Security

- **Row Level Security (RLS)**: Enabled on all tables
- **Authentication**: All endpoints require Clerk authentication
- **Authorization**: Admin/User role separation in database
- **Image Storage**: Public bucket for menu images

## 📊 Database Schema

### Tables:
- `profiles`: User data synced from Clerk
- `menu_items`: Restaurant menu
- `orders`: Customer orders
- `order_items`: Normalized order line items
- `analytics_events`: Event logging for analytics

### Policies:
- Users see only their own data
- Admins see all data
- Public can view available menu items only

## 🔧 Environment Variables

Both apps require `.env` file:

```
CLERK_PUBLISHABLE_KEY=pk_test_xxxxx
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJxxxxx
```

## 📦 Dependencies

### Both Apps Use:
- `clerk_flutter`: Authentication
- `supabase_flutter`: Backend
- `go_router`: Navigation
- `provider`: State management
- `flutter_dotenv`: Environment variables
- `google_fonts`: Typography

## 🚢 Deployment

### Admin App:
```bash
flutter build apk    # Android
flutter build ipa    # iOS
flutter build web    # Web
```

### User App:
```bash
flutter build apk    # Android
flutter build ipa    # iOS
flutter build web    # Web
```

## 🐛 Troubleshooting

### Common Issues:

**Auth not working:**
- Verify `CLERK_PUBLISHABLE_KEY` is correct
- Check Clerk dashboard for OAuth configuration

**Database connection failed:**
- Verify `SUPABASE_URL` and `SUPABASE_ANON_KEY`
- Check Supabase project is active

**Missing menu images:**
- Create `menu-images` bucket in Supabase Storage
- Ensure bucket is set to public

## 📝 Notes

- Both apps share the same Supabase backend
- Separate Flutter projects allow independent development
- Use same `.env` credentials in both apps
- Clerk handles user authentication and sync to profiles table

## 📚 Additional Resources

- [Supabase Docs](https://supabase.com/docs)
- [Clerk Documentation](https://clerk.com/docs)
- [Flutter Docs](https://flutter.dev/docs)
- [GoRouter Guide](https://pub.dev/packages/go_router)

---

**Need help?** Check individual app README files for more details.
