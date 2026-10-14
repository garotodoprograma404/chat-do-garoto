import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// An address found by its CEP.
typedef CepAddress = ({
  String street,
  String district,
  String city,
  String state,
});

/// The CEP does not exist.
class CepNotFound implements Exception {
  const CepNotFound();
}

/// No internet, or the services did not answer.
class CepUnavailable implements Exception {
  const CepUnavailable();
}

/// Finds an address by its CEP. Only the 8 digits leave the
/// phone, and only when the user taps "Buscar CEP".
abstract interface class CepLookup {
  /// Throws [CepNotFound] or [CepUnavailable].
  Future<CepAddress> find(String cep);
}

/// ViaCEP, then BrasilAPI when ViaCEP fails: HTTPS, no cookies,
/// 5 seconds each. Nothing is logged.
class HttpCepLookup implements CepLookup {
  HttpCepLookup({HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;
  static const _timeout = Duration(seconds: 5);

  @override
  Future<CepAddress> find(String cep) async {
    if (!RegExp(r'^\d{8}$').hasMatch(cep)) throw const CepNotFound();
    try {
      return await _viaCep(cep);
    } on CepNotFound {
      rethrow;
    } on Object {
      // ViaCEP down or unreachable: the other service.
    }
    try {
      return await _brasilApi(cep);
    } on CepNotFound {
      rethrow;
    } on Object {
      throw const CepUnavailable();
    }
  }

  Future<(int, Object?)> _get(Uri uri) async {
    final client = _client()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      return (response.statusCode, body.isEmpty ? null : jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }

  Future<CepAddress> _viaCep(String cep) async {
    final (status, json) = await _get(
      Uri.https('viacep.com.br', '/ws/$cep/json/'),
    );
    if (status == 400) throw const CepNotFound();
    if (status != 200 || json is! Map<String, Object?>) {
      throw const CepUnavailable();
    }
    if (json['erro'] != null) throw const CepNotFound();
    return (
      street: json['logradouro'] as String? ?? '',
      district: json['bairro'] as String? ?? '',
      city: json['localidade'] as String? ?? '',
      state: json['uf'] as String? ?? '',
    );
  }

  Future<CepAddress> _brasilApi(String cep) async {
    final (status, json) = await _get(
      Uri.https('brasilapi.com.br', '/api/cep/v1/$cep'),
    );
    if (status == 404) throw const CepNotFound();
    if (status != 200 || json is! Map<String, Object?>) {
      throw const CepUnavailable();
    }
    return (
      street: json['street'] as String? ?? '',
      district: json['neighborhood'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
    );
  }
}

/// The lookup the client form uses; tests set a fake.
CepLookup cepLookup = HttpCepLookup();
