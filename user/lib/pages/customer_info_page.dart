import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/customer_info_provider.dart';
import '../theme/bauhaus_theme.dart';

class CustomerInfoPage extends StatefulWidget {
  const CustomerInfoPage({super.key});

  @override
  State<CustomerInfoPage> createState() => _CustomerInfoPageState();
}

class _CustomerInfoPageState extends State<CustomerInfoPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  String? _selectedGender;
  String? _selectedPreference;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Welcome',
          style: BauhausTheme.heading(size: 22, weight: FontWeight.w700),
        ),
        backgroundColor: BauhausTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Details',
                style: BauhausTheme.heading(size: 26, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Auto-deleted after 24 hours',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: BauhausTheme.mediumGrey,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'FULL NAME',
                  hintText: 'Your name',
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Name required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'PHONE',
                  hintText: '10-digit number',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.isEmpty ?? true) {
                    return 'Phone required';
                  }
                  if (!RegExp(r'^[0-9]{10}$').hasMatch(value!)) {
                    return 'Enter 10-digit number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                decoration: const InputDecoration(
                  labelText: 'GENDER',
                ),
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: item.child,
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Select gender';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _selectedPreference,
                decoration: const InputDecoration(
                  labelText: 'PREFERENCE',
                ),
                items: const [
                  DropdownMenuItem(value: 'veg', child: Text('Vegetarian')),
                  DropdownMenuItem(value: 'non_veg', child: Text('Non-Veg')),
                ]
                    .map((item) => DropdownMenuItem(
                          value: item.value,
                          child: item.child,
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPreference = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Select preference';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),
              Consumer<CustomerInfoProvider>(
                builder: (context, provider, _) {
                  return Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: provider.isLoading
                              ? null
                              : () async {
                                  if (_formKey.currentState!.validate()) {
                                    final success =
                                        await provider.submitCustomerInfo(
                                      name: _nameController.text,
                                      phone: _phoneController.text,
                                      gender: _selectedGender!,
                                      preference: _selectedPreference!,
                                    );

                                    if (!context.mounted) return;
                                    if (success) {
                                      context.go('/');
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text(provider.error ?? 'Error'),
                                          backgroundColor:
                                              BauhausTheme.accentRed,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: provider.isLoading
                                ? BauhausTheme.mediumGrey
                                : BauhausTheme.accentRed,
                            foregroundColor: BauhausTheme.onAccent,
                          ),
                          child: provider.isLoading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      BauhausTheme.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  'CONTINUE',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => context.go('/'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: BauhausTheme.primaryBlack,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'SKIP FOR NOW',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: BauhausTheme.primaryBlack,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
