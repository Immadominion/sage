import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/solana.dart';
import 'package:tld_parser/tld_parser.dart';

import 'package:sage/core/config/env_config.dart';

/// Resolves Solana wallet addresses ↔ AllDomains ANS names.
///
/// Uses `tld_parser_dart` for:
/// - Reverse lookup: wallet address → main domain name
/// - Forward lookup: domain name → owner wallet address
///
/// Results are cached in-memory so the same input is only resolved once.
class DomainResolver {
  DomainResolver._();

  static final _instance = DomainResolver._();
  factory DomainResolver() => _instance;

  late final RpcClient _rpc = RpcClient(EnvConfig.solanaRpcUrl);
  late final TldParser _parser = TldParser(_rpc);

  /// Cache: wallet address → domain name (null = no domain found).
  final Map<String, String?> _cache = {};

  /// Cache: domain → wallet address (null = not found).
  final Map<String, String?> _addressCache = {};

  /// Resolve a wallet address to its AllDomains main domain.
  ///
  /// Returns the full domain (e.g. `miester.abc`) or `null` if no
  /// main domain is set for this wallet.
  ///
  /// Results are cached — subsequent calls for the same address
  /// return instantly from memory.
  Future<String?> resolve(String walletAddress) async {
    // Check cache first
    if (_cache.containsKey(walletAddress)) {
      return _cache[walletAddress];
    }

    try {
      final pubkey = Ed25519HDPublicKey.fromBase58(walletAddress);
      final mainDomain = await _parser.tryGetMainDomain(pubkey);

      final domain = mainDomain?.fullDomain;
      _cache[walletAddress] = domain;
      return domain;
    } catch (e) {
      debugPrint('[DomainResolver] Failed to resolve $walletAddress: $e');
      _cache[walletAddress] = null;
      return null;
    }
  }

  /// Resolve a domain name to its owner wallet address.
  ///
  /// Supports AllDomains TLDs (.abc, .bonk, .skr, .poor, etc.).
  /// Input should include the TLD, e.g. `miester.abc`.
  ///
  /// Returns the base58 wallet address or `null` if not found.
  Future<String?> resolveAddress(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (_addressCache.containsKey(normalized)) {
      return _addressCache[normalized];
    }

    try {
      final owner = await _parser.getOwnerFromDomainTld(normalized);
      final address = owner?.toBase58();
      _addressCache[normalized] = address;
      return address;
    } catch (e) {
      debugPrint('[DomainResolver] Failed to resolve domain $domain: $e');
      _addressCache[normalized] = null;
      return null;
    }
  }

  /// Whether a string looks like a domain (has a dot, no spaces).
  static bool isDomain(String input) {
    final trimmed = input.trim();
    return trimmed.contains('.') && !trimmed.contains(' ') && trimmed.length > 3;
  }

  /// Whether a string looks like a valid base58 Solana address.
  static bool isValidAddress(String input) {
    final trimmed = input.trim();
    if (trimmed.length < 32 || trimmed.length > 44) return false;
    try {
      Ed25519HDPublicKey.fromBase58(trimmed);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get cached result without making a network call.
  String? getCached(String walletAddress) => _cache[walletAddress];

  /// Whether a result (including null) is cached for this address.
  bool isCached(String walletAddress) => _cache.containsKey(walletAddress);
}

/// Provider for the singleton DomainResolver.
final domainResolverProvider = Provider<DomainResolver>((ref) {
  return DomainResolver();
});

/// FutureProvider that resolves a wallet address → domain name.
/// Auto-caches so it won't re-fetch on rebuild.
final domainNameProvider = FutureProvider.family<String?, String>((
  ref,
  walletAddress,
) async {
  final resolver = ref.read(domainResolverProvider);
  return resolver.resolve(walletAddress);
});

/// FutureProvider that resolves a domain name → wallet address.
final domainAddressProvider = FutureProvider.family<String?, String>((
  ref,
  domain,
) async {
  final resolver = ref.read(domainResolverProvider);
  return resolver.resolveAddress(domain);
});
