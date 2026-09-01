import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/customer_info_provider.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  @override
  void initState() {
    super.initState();
    final provider = context.read<CustomerInfoProvider>();
    Future.microtask(() => provider.fetchCustomers());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Details'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<CustomerInfoProvider>().fetchCustomers();
            },
          ),
        ],
      ),
      body: Consumer<CustomerInfoProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${provider.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      provider.fetchCustomers();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (provider.customers.isEmpty) {
            return const Center(
              child: Text('No customers yet'),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Phone')),
              ],
              rows: provider.customers.map((customer) {
                return DataRow(
                  cells: [
                    DataCell(Text(customer.name)),
                    DataCell(Text(customer.phone)),
                  ],
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }


}
