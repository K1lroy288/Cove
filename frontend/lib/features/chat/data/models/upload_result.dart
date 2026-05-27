class UploadResult {
  final String url;
  final String type;
  final String fileName;
  final int fileSize;

  const UploadResult({
    required this.url,
    required this.type,
    required this.fileName,
    required this.fileSize,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      url: json['url'] as String,
      type: json['type'] as String,
      fileName: json['file_name'] as String,
      fileSize: (json['file_size'] as num).toInt(),
    );
  }
}
