import 'package:flutter/material.dart';
import 'package:mygobuddy/providers/dashboard_provider.dart';
import 'package:mygobuddy/utils/constants.dart';
import 'package:mygobuddy/utils/localizations.dart';
import 'package:provider/provider.dart';

class AddBankAccountScreen extends StatefulWidget {
  const AddBankAccountScreen({super.key});

  @override
  State<AddBankAccountScreen> createState() => _AddBankAccountScreenState();
}

class _AddBankAccountScreenState extends State<AddBankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Form controllers
  final _fullNameController = TextEditingController();
  final _streetAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _routingNumberController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _sortCodeController = TextEditingController();
  final _bsbController = TextEditingController();
  final _transitNumberController = TextEditingController();
  final _institutionNumberController = TextEditingController();

  String _selectedCountry = 'US';
  String _selectedAccountType = 'individual';

  @override
  void dispose() {
    _fullNameController.dispose();
    _streetAddressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _routingNumberController.dispose();
    _accountNumberController.dispose();
    _sortCodeController.dispose();
    _bsbController.dispose();
    _transitNumberController.dispose();
    _institutionNumberController.dispose();
    super.dispose();
  }

  Future<void> _saveAccount() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Consolidate all details into a single map
        final Map<String, dynamic> details = {
          'country': _selectedCountry,
          'account_holder_name': _fullNameController.text,
          'account_holder_type': _selectedAccountType,
          'address': {
            'street': _streetAddressController.text,
            'city': _cityController.text,
            'state': _stateController.text,
            'postal_code': _postalCodeController.text,
          },
          'account_number': _accountNumberController.text,
        };

        // Add country-specific fields only if they have values
        if (_routingNumberController.text.isNotEmpty) {
          details['routing_number'] = _routingNumberController.text;
        }
        if (_sortCodeController.text.isNotEmpty) {
          details['sort_code'] = _sortCodeController.text;
        }
        if (_bsbController.text.isNotEmpty) {
          details['bsb'] = _bsbController.text;
        }
        if (_transitNumberController.text.isNotEmpty) {
          details['transit_number'] = _transitNumberController.text;
        }
        if (_institutionNumberController.text.isNotEmpty) {
          details['institution_number'] = _institutionNumberController.text;
        }

        // The RPC function now expects a single parameter 'p_details' which is a JSONB object
        await supabase.rpc('add_bank_payout_method', params: {'p_details': details});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).translate('bankAccountAddedSuccess')),
              backgroundColor: Colors.green,
            ),
          );
          // On success, force a refresh of the dashboard data
          await Provider.of<DashboardProvider>(context, listen: false)
              .fetchDashboardData(force: true);
          Navigator.of(context).pop(true); // Return true to indicate success
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).translate('errorAddingAccount') + ': $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.translate('addBankAccount')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDropdown(
                  label: localizations.translate('country'),
                  value: _selectedCountry,
                  icon: Icons.public,
                  items: [
                    DropdownMenuItem(value: 'US', child: Text(localizations.translate('unitedStates'))),
                    DropdownMenuItem(value: 'GB', child: Text(localizations.translate('unitedKingdom'))),
                    DropdownMenuItem(value: 'CA', child: Text(localizations.translate('canada'))),
                    DropdownMenuItem(value: 'AU', child: Text(localizations.translate('australia'))),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCountry = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(localizations.translate('accountHolderInformation')),
                _buildTextField(
                  controller: _fullNameController,
                  label: localizations.translate('fullName'),
                  icon: Icons.person_outline,
                  validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
                ),
                _buildDropdown(
                  label: localizations.translate('accountType'),
                  value: _selectedAccountType,
                  icon: Icons.business_center_outlined,
                  items: [
                    DropdownMenuItem(value: 'individual', child: Text(localizations.translate('individual'))),
                    DropdownMenuItem(value: 'company', child: Text(localizations.translate('company'))),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedAccountType = value;
                      });
                    }
                  },
                ),
                _buildTextField(
                  controller: _streetAddressController,
                  label: localizations.translate('streetAddress'),
                  icon: Icons.home_outlined,
                  validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
                ),
                _buildTextField(
                  controller: _cityController,
                  label: localizations.translate('city'),
                  icon: Icons.location_city_outlined,
                  validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _stateController,
                        label: localizations.translate('stateProvince'),
                        icon: Icons.map_outlined,
                        validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _postalCodeController,
                        label: localizations.translate('postalCode'),
                        icon: Icons.markunread_mailbox_outlined,
                        validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(localizations.translate('bankDetails')),
                ..._buildCountrySpecificFields(localizations),
                const SizedBox(height: 80), // Space for the button
              ],
            ),
          ),
        ),
      ),
      bottomSheet: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveAccount,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
                : Text(localizations.translate('saveAccount')),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: validator,
        keyboardType: keyboardType,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  List<Widget> _buildCountrySpecificFields(AppLocalizations localizations) {
    switch (_selectedCountry) {
      case 'US':
        return [
          _buildTextField(
            controller: _routingNumberController,
            label: localizations.translate('routingNumber'),
            icon: Icons.numbers,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
          _buildTextField(
            controller: _accountNumberController,
            label: localizations.translate('accountNumber'),
            icon: Icons.account_balance_wallet_outlined,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
        ];
      case 'GB':
        return [
          _buildTextField(
            controller: _sortCodeController,
            label: localizations.translate('sortCode'),
            icon: Icons.numbers,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
          _buildTextField(
            controller: _accountNumberController,
            label: localizations.translate('accountNumber'),
            icon: Icons.account_balance_wallet_outlined,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
        ];
      case 'CA':
        return [
          _buildTextField(
            controller: _transitNumberController,
            label: localizations.translate('transitNumber'),
            icon: Icons.numbers,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
          _buildTextField(
            controller: _institutionNumberController,
            label: localizations.translate('institutionNumber'),
            icon: Icons.domain,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
          _buildTextField(
            controller: _accountNumberController,
            label: localizations.translate('accountNumber'),
            icon: Icons.account_balance_wallet_outlined,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
        ];
      case 'AU':
        return [
          _buildTextField(
            controller: _bsbController,
            label: localizations.translate('bsb'),
            icon: Icons.numbers,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
          _buildTextField(
            controller: _accountNumberController,
            label: localizations.translate('accountNumber'),
            icon: Icons.account_balance_wallet_outlined,
            keyboardType: TextInputType.number,
            validator: (value) => value!.isEmpty ? localizations.translate('fieldRequired') : null,
          ),
        ];
      default:
        return [];
    }
  }
}
