class DiagnosticTroubleCode {
  final String code;
  final bool isPending;

  const DiagnosticTroubleCode({
    required this.code,
    required this.isPending,
  });

  /// Parses semicolon-separated DTC tokens from ESP32-S3 response (`"P0122:S;C0035:P"`).
  static List<DiagnosticTroubleCode> parseList(String rawPayload) {
    final trimmed = rawPayload.trim();
    if (trimmed.isEmpty) return const [];

    final List<DiagnosticTroubleCode> results = [];
    final tokens = trimmed.split(';');
    for (final rawToken in tokens) {
      final token = rawToken.trim();
      if (token.isEmpty) continue;
      final parts = token.split(':');
      final codeStr = parts.first.trim().toUpperCase();
      if (codeStr.isEmpty) continue;
      final isPending = parts.length > 1 && parts[1].trim().toUpperCase() == 'P';
      if (!results.any((e) => e.code == codeStr)) {
        results.add(DiagnosticTroubleCode(
          code: codeStr,
          isPending: isPending,
        ));
      }
    }
    return results;
  }

  String get statusLabelCz => isPending ? 'Čekající (Mode 07)' : 'Uložená (Mode 03)';

  String get systemCategoryCz {
    if (code.isEmpty) return 'Neznámý systém';
    switch (code[0].toUpperCase()) {
      case 'P':
        return 'Motor a řízení (Powertrain)';
      case 'C':
        return 'Podvozek a ABS (Chassis)';
      case 'B':
        return 'Elektronika (Body)';
      case 'U':
        return 'Sběrnice CAN (Network)';
      default:
        return 'Řídicí jednotka (ECU)';
    }
  }

  String get descriptionCz {
    final normalized = code.trim().toUpperCase();
    final known = _knownDescriptionsCz[normalized];
    if (known != null) return known;

    if (normalized.startsWith('P0')) {
      return 'Standardní závada řízení motoru / vstřikování (SAE J2012)';
    } else if (normalized.startsWith('P1') ||
        normalized.startsWith('P2') ||
        normalized.startsWith('P3')) {
      return 'Specifická závada motoru / emisního systému výrobce';
    } else if (normalized.startsWith('C')) {
      return 'Závada snímače kol, ABS nebo kontroly trakce';
    } else if (normalized.startsWith('B')) {
      return 'Závada palubní elektroniky nebo přístrojového štítu';
    } else if (normalized.startsWith('U')) {
      return 'Chyba komunikace mezi jednotkami na sběrnici CAN';
    }
    return 'Diagnostický chybový kód řídicí jednotky';
  }

  static const Map<String, String> _knownDescriptionsCz = {
    'P0105': 'Snímač tlaku v sacím potrubí (MAP) – porucha obvodu',
    'P0107': 'Snímač tlaku v sání (MAP) – nízké napětí signálu',
    'P0108': 'Snímač tlaku v sání (MAP) – vysoké napětí signálu',
    'P0110': 'Snímač teploty nasávaného vzduchu (IAT) – porucha obvodu',
    'P0112': 'Snímač teploty nasávaného vzduchu (IAT) – nízký signál',
    'P0113': 'Snímač teploty nasávaného vzduchu (IAT) – vysoký signál',
    'P0115': 'Snímač teploty chladicí kapaliny (ECT) – porucha obvodu',
    'P0117': 'Snímač teploty chladicí kapaliny (ECT) – nízký signál (zkrat)',
    'P0118': 'Snímač teploty chladicí kapaliny (ECT) – vysoký signál (rozpojeno)',
    'P0120': 'Snímač polohy škrticí klapky (TPS) – porucha obvodu A',
    'P0122': 'Snímač polohy škrticí klapky (TPS) – nízké napětí signálu',
    'P0123': 'Snímač polohy škrticí klapky (TPS) – vysoké napětí signálu',
    'P0130': 'Lambda sonda (O2) – porucha obvodu (řada 1, snímač 1)',
    'P0135': 'Vyhřívání lambda sondy (O2) – porucha obvodu',
    'P0201': 'Vstřikovač válce 1 – porucha obvodu',
    'P0202': 'Vstřikovač válce 2 – porucha obvodu',
    'P0203': 'Vstřikovač válce 3 – porucha obvodu',
    'P0204': 'Vstřikovač válce 4 – porucha obvodu',
    'P0230': 'Palivové čerpadlo – porucha primárního obvodu relé',
    'P0300': 'Zjištěno náhodné/vícenásobné vynechávání zapalování (Misfire)',
    'P0301': 'Válec 1 – zjištěno vynechávání zapalování',
    'P0302': 'Válec 2 – zjištěno vynechávání zapalování',
    'P0335': 'Snímač polohy klikového hřídele (CKP) – porucha obvodu',
    'P0340': 'Snímač polohy vačkového hřídele (CMP) – porucha obvodu',
    'P0351': 'Zapalovací cívka A – porucha primárního/sekundárního obvodu',
    'P0352': 'Zapalovací cívka B – porucha primárního/sekundárního obvodu',
    'P0410': 'Systém sekundárního vzduchu (PAIR / AIS) – porucha funkce',
    'P0420': 'Účinnost katalyzátoru pod prahovou hodnotou',
    'P0500': 'Snímač rychlosti motocyklu (VSS) – chybějící signál',
    'P0505': 'Řízení volnoběžných otáček (IACV) – porucha funkce',
    'P0560': 'Napětí palubní sítě – porucha napájení ECU',
    'P0562': 'Napětí baterie / dobíjení – příliš nízké napětí',
    'P0563': 'Napětí baterie / regulátoru – příliš vysoké napětí (přebíjení)',
    'P0600': 'Sériová komunikační linka ECU – porucha přenosu',
    'P0704': 'Spínač spojkové páčky – porucha vstupního obvodu',
    'P0850': 'Spínač neutrálu / bočního stojánku – porucha obvodu',
    'P2100': 'Ovládací motor elektronické klapky (Ride-by-Wire) – obvod',
    'C0031': 'Snímač otáček předního kola (ABS) – porucha signálu',
    'C0035': 'Snímač otáček předního kola (ABS) – rozpojený obvod',
    'C0040': 'Snímač otáček zadního kola (ABS) – porucha signálu',
    'U0100': 'Ztráta komunikace CAN s řídicí jednotkou motoru (ECM/PCM)',
    'U0121': 'Ztráta komunikace CAN s jednotkou ABS',
    'U0155': 'Ztráta komunikace CAN s přístrojovým štítem',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticTroubleCode &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          isPending == other.isPending;

  @override
  int get hashCode => Object.hash(code, isPending);
}
