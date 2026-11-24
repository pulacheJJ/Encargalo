import '../../../core/network/api_client.dart';
import '../domain/profile_gateway.dart';

class ProfileRepository implements ProfileGateway {
  final ApiClient api;
  ProfileRepository(this.api);
  @override
  Future<Map<String, dynamic>> privateContact(String owner) async {
    final rows = await api.select(
      'profile_contacts',
      query: {'owner_id': 'eq.$owner', 'limit': 1},
    );
    return rows.isEmpty ? <String, dynamic>{} : rows.single;
  }

  @override
  Future<void> save(Map<String, dynamic> details) async {
    await api.rpc('save_profile_details', {'p_data': details});
  }
}
