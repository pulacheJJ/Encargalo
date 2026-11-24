abstract interface class ProfileGateway {
  Future<Map<String, dynamic>> privateContact(String owner);
  Future<void> save(Map<String, dynamic> details);
}
