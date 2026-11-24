class LocationEntry {
  final String code, region, province, district;
  const LocationEntry({
    required this.code,
    required this.region,
    required this.province,
    required this.district,
  });
  factory LocationEntry.fromJson(Map<String, dynamic> json) => LocationEntry(
    code: json['code'],
    region: json['region'],
    province: json['province'],
    district: json['district'],
  );
  String get label => '$district · $province · $region';
}

abstract interface class LocationCatalog {
  Future<List<LocationEntry>> bundled();
  Future<List<LocationEntry>> refresh(String region);
}
