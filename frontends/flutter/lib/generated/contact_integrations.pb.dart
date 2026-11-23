//
//  Generated code. Do not modify.
//  source: contact_integrations.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'contact_integrations.pbenum.dart';
import 'google/protobuf/timestamp.pb.dart' as $14;

export 'contact_integrations.pbenum.dart';

/// A live health report for every SMS and email integration an admin has configured -- the response to
/// [`GetContactIntegrationsStatus`](#grpc-api-GetContactIntegrationsStatus). Everything here is
/// gathered *on demand* by actually calling each provider's own API (and, for email, looking up the
/// sending domains' SPF/DKIM/DMARC DNS records), so it reflects reality right now rather than what
/// the admin last typed into the form -- and it's therefore slow (several outbound HTTP calls, run
/// in parallel), which is why it's its own RPC instead of part of
/// [`ServerConfiguration`](#rellm-ServerConfiguration). Contains no secrets.
class ContactIntegrationsStatus extends $pb.GeneratedMessage {
  factory ContactIntegrationsStatus({
    $14.Timestamp? checkedAt,
    $core.Iterable<ProviderStatus>? smsProviders,
    $core.Iterable<ProviderStatus>? emailProviders,
    $core.Iterable<EmailDomainStatus>? emailDomains,
  }) {
    final $result = create();
    if (checkedAt != null) {
      $result.checkedAt = checkedAt;
    }
    if (smsProviders != null) {
      $result.smsProviders.addAll(smsProviders);
    }
    if (emailProviders != null) {
      $result.emailProviders.addAll(emailProviders);
    }
    if (emailDomains != null) {
      $result.emailDomains.addAll(emailDomains);
    }
    return $result;
  }
  ContactIntegrationsStatus._() : super();
  factory ContactIntegrationsStatus.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ContactIntegrationsStatus.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ContactIntegrationsStatus', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOM<$14.Timestamp>(1, _omitFieldNames ? '' : 'checkedAt', subBuilder: $14.Timestamp.create)
    ..pc<ProviderStatus>(2, _omitFieldNames ? '' : 'smsProviders', $pb.PbFieldType.PM, subBuilder: ProviderStatus.create)
    ..pc<ProviderStatus>(3, _omitFieldNames ? '' : 'emailProviders', $pb.PbFieldType.PM, subBuilder: ProviderStatus.create)
    ..pc<EmailDomainStatus>(4, _omitFieldNames ? '' : 'emailDomains', $pb.PbFieldType.PM, subBuilder: EmailDomainStatus.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ContactIntegrationsStatus clone() => ContactIntegrationsStatus()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ContactIntegrationsStatus copyWith(void Function(ContactIntegrationsStatus) updates) => super.copyWith((message) => updates(message as ContactIntegrationsStatus)) as ContactIntegrationsStatus;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ContactIntegrationsStatus create() => ContactIntegrationsStatus._();
  ContactIntegrationsStatus createEmptyInstance() => create();
  static $pb.PbList<ContactIntegrationsStatus> createRepeated() => $pb.PbList<ContactIntegrationsStatus>();
  @$core.pragma('dart2js:noInline')
  static ContactIntegrationsStatus getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ContactIntegrationsStatus>(create);
  static ContactIntegrationsStatus? _defaultInstance;

  /// When the server gathered this report.
  @$pb.TagNumber(1)
  $14.Timestamp get checkedAt => $_getN(0);
  @$pb.TagNumber(1)
  set checkedAt($14.Timestamp v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasCheckedAt() => $_has(0);
  @$pb.TagNumber(1)
  void clearCheckedAt() => clearField(1);
  @$pb.TagNumber(1)
  $14.Timestamp ensureCheckedAt() => $_ensure(0);

  /// One entry per SMS provider (Twilio/Bird/Telnyx) that is enabled or has any configuration
  /// stored, in the order the server would try them for verification codes.
  @$pb.TagNumber(2)
  $core.List<ProviderStatus> get smsProviders => $_getList(1);

  /// One entry per email provider (Stalwart/Postmark/SendGrid/Mailgun) that is enabled or has any
  /// configuration stored, in the order the server would try them.
  @$pb.TagNumber(3)
  $core.List<ProviderStatus> get emailProviders => $_getList(2);

  /// DNS-level email authentication (SPF/DKIM/DMARC) for each distinct domain the enabled email
  /// providers send from. Independent of which provider is used -- this is what receiving mail
  /// servers (Gmail, Outlook, ...) actually check.
  @$pb.TagNumber(4)
  $core.List<EmailDomainStatus> get emailDomains => $_getList(3);
}

/// The health of one SMS or email provider integration.
class ProviderStatus extends $pb.GeneratedMessage {
  factory ProviderStatus({
    $core.String? provider,
    $core.String? displayName,
    $core.bool? enabled,
    $core.bool? configured,
    StatusLevel? level,
    $core.String? summary,
    $core.Iterable<StatusCheck>? checks,
    $core.Iterable<StatusMetric>? metrics,
    $core.String? dashboardUrl,
  }) {
    final $result = create();
    if (provider != null) {
      $result.provider = provider;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (enabled != null) {
      $result.enabled = enabled;
    }
    if (configured != null) {
      $result.configured = configured;
    }
    if (level != null) {
      $result.level = level;
    }
    if (summary != null) {
      $result.summary = summary;
    }
    if (checks != null) {
      $result.checks.addAll(checks);
    }
    if (metrics != null) {
      $result.metrics.addAll(metrics);
    }
    if (dashboardUrl != null) {
      $result.dashboardUrl = dashboardUrl;
    }
    return $result;
  }
  ProviderStatus._() : super();
  factory ProviderStatus.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ProviderStatus.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ProviderStatus', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'provider')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOB(3, _omitFieldNames ? '' : 'enabled')
    ..aOB(4, _omitFieldNames ? '' : 'configured')
    ..e<StatusLevel>(5, _omitFieldNames ? '' : 'level', $pb.PbFieldType.OE, defaultOrMaker: StatusLevel.STATUS_LEVEL_UNKNOWN, valueOf: StatusLevel.valueOf, enumValues: StatusLevel.values)
    ..aOS(6, _omitFieldNames ? '' : 'summary')
    ..pc<StatusCheck>(7, _omitFieldNames ? '' : 'checks', $pb.PbFieldType.PM, subBuilder: StatusCheck.create)
    ..pc<StatusMetric>(8, _omitFieldNames ? '' : 'metrics', $pb.PbFieldType.PM, subBuilder: StatusMetric.create)
    ..aOS(9, _omitFieldNames ? '' : 'dashboardUrl')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ProviderStatus clone() => ProviderStatus()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ProviderStatus copyWith(void Function(ProviderStatus) updates) => super.copyWith((message) => updates(message as ProviderStatus)) as ProviderStatus;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ProviderStatus create() => ProviderStatus._();
  ProviderStatus createEmptyInstance() => create();
  static $pb.PbList<ProviderStatus> createRepeated() => $pb.PbList<ProviderStatus>();
  @$core.pragma('dart2js:noInline')
  static ProviderStatus getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProviderStatus>(create);
  static ProviderStatus? _defaultInstance;

  /// Stable lowercase identifier: `twilio`, `bird`, `telnyx`, `postmark`, `sendgrid`, `mailgun` or
  /// `stalwart`.
  @$pb.TagNumber(1)
  $core.String get provider => $_getSZ(0);
  @$pb.TagNumber(1)
  set provider($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasProvider() => $_has(0);
  @$pb.TagNumber(1)
  void clearProvider() => clearField(1);

  /// Human-friendly name, e.g. "Twilio", "SendGrid".
  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  /// Whether the admin has switched this provider on.
  @$pb.TagNumber(3)
  $core.bool get enabled => $_getBF(2);
  @$pb.TagNumber(3)
  set enabled($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEnabled() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnabled() => clearField(3);

  /// Whether it has all the credentials/settings it needs to attempt a send.
  @$pb.TagNumber(4)
  $core.bool get configured => $_getBF(3);
  @$pb.TagNumber(4)
  set configured($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConfigured() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfigured() => clearField(4);

  /// The overall verdict: the worst `level` among `checks`, or `STATUS_LEVEL_DISABLED`.
  @$pb.TagNumber(5)
  StatusLevel get level => $_getN(4);
  @$pb.TagNumber(5)
  set level(StatusLevel v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasLevel() => $_has(4);
  @$pb.TagNumber(5)
  void clearLevel() => clearField(5);

  /// A one-sentence, plain-language summary suitable for a headline, e.g. "Ready to send -- 1 thing
  /// needs attention."
  @$pb.TagNumber(6)
  $core.String get summary => $_getSZ(5);
  @$pb.TagNumber(6)
  set summary($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSummary() => $_has(5);
  @$pb.TagNumber(6)
  void clearSummary() => clearField(6);

  /// Individual pass/warn/fail checks, e.g. "API credentials valid", "Sender number can send SMS",
  /// "Domain authenticated (DKIM + SPF)".
  @$pb.TagNumber(7)
  $core.List<StatusCheck> get checks => $_getList(6);

  /// Numbers the provider reported, e.g. account balance, messages sent in the last 30 days,
  /// delivery/bounce rates.
  @$pb.TagNumber(8)
  $core.List<StatusMetric> get metrics => $_getList(7);

  /// A link to this provider's own dashboard, if it has a stable one.
  @$pb.TagNumber(9)
  $core.String get dashboardUrl => $_getSZ(8);
  @$pb.TagNumber(9)
  set dashboardUrl($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasDashboardUrl() => $_has(8);
  @$pb.TagNumber(9)
  void clearDashboardUrl() => clearField(9);
}

/// One pass/warn/fail line within a [`ProviderStatus`](#rellm-ProviderStatus) or
/// [`EmailDomainStatus`](#rellm-EmailDomainStatus).
class StatusCheck extends $pb.GeneratedMessage {
  factory StatusCheck({
    $core.String? name,
    StatusLevel? level,
    $core.String? detail,
    $core.String? fixHint,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (level != null) {
      $result.level = level;
    }
    if (detail != null) {
      $result.detail = detail;
    }
    if (fixHint != null) {
      $result.fixHint = fixHint;
    }
    return $result;
  }
  StatusCheck._() : super();
  factory StatusCheck.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StatusCheck.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StatusCheck', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..e<StatusLevel>(2, _omitFieldNames ? '' : 'level', $pb.PbFieldType.OE, defaultOrMaker: StatusLevel.STATUS_LEVEL_UNKNOWN, valueOf: StatusLevel.valueOf, enumValues: StatusLevel.values)
    ..aOS(3, _omitFieldNames ? '' : 'detail')
    ..aOS(4, _omitFieldNames ? '' : 'fixHint')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StatusCheck clone() => StatusCheck()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StatusCheck copyWith(void Function(StatusCheck) updates) => super.copyWith((message) => updates(message as StatusCheck)) as StatusCheck;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusCheck create() => StatusCheck._();
  StatusCheck createEmptyInstance() => create();
  static $pb.PbList<StatusCheck> createRepeated() => $pb.PbList<StatusCheck>();
  @$core.pragma('dart2js:noInline')
  static StatusCheck getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StatusCheck>(create);
  static StatusCheck? _defaultInstance;

  /// Short name, e.g. "API credentials".
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  StatusLevel get level => $_getN(1);
  @$pb.TagNumber(2)
  set level(StatusLevel v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasLevel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLevel() => clearField(2);

  /// What was found, e.g. "Authenticated as account AC12…".
  @$pb.TagNumber(3)
  $core.String get detail => $_getSZ(2);
  @$pb.TagNumber(3)
  set detail($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDetail() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetail() => clearField(3);

  /// Optional advice for fixing a `WARNING`/`ERROR`, e.g. "Add a DMARC record at
  /// _dmarc.example.com."
  @$pb.TagNumber(4)
  $core.String get fixHint => $_getSZ(3);
  @$pb.TagNumber(4)
  set fixHint($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFixHint() => $_has(3);
  @$pb.TagNumber(4)
  void clearFixHint() => clearField(4);
}

/// A single labelled number/string a provider reported, e.g. `{label: "Balance", value: "$12.34"}`.
class StatusMetric extends $pb.GeneratedMessage {
  factory StatusMetric({
    $core.String? label,
    $core.String? value,
    $core.String? detail,
  }) {
    final $result = create();
    if (label != null) {
      $result.label = label;
    }
    if (value != null) {
      $result.value = value;
    }
    if (detail != null) {
      $result.detail = detail;
    }
    return $result;
  }
  StatusMetric._() : super();
  factory StatusMetric.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StatusMetric.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StatusMetric', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'label')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..aOS(3, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StatusMetric clone() => StatusMetric()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StatusMetric copyWith(void Function(StatusMetric) updates) => super.copyWith((message) => updates(message as StatusMetric)) as StatusMetric;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusMetric create() => StatusMetric._();
  StatusMetric createEmptyInstance() => create();
  static $pb.PbList<StatusMetric> createRepeated() => $pb.PbList<StatusMetric>();
  @$core.pragma('dart2js:noInline')
  static StatusMetric getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StatusMetric>(create);
  static StatusMetric? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get label => $_getSZ(0);
  @$pb.TagNumber(1)
  set label($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLabel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLabel() => clearField(1);

  /// Already formatted for display.
  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => clearField(2);

  /// Optional extra context, e.g. "last 30 days".
  @$pb.TagNumber(3)
  $core.String get detail => $_getSZ(2);
  @$pb.TagNumber(3)
  set detail($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDetail() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetail() => clearField(3);
}

/// Email-authentication (SPF/DKIM/DMARC) state for one sending domain, from live DNS lookups plus
/// whatever the providers' APIs report about domain verification.
class EmailDomainStatus extends $pb.GeneratedMessage {
  factory EmailDomainStatus({
    $core.String? domain,
    $core.Iterable<$core.String>? usedBy,
    StatusLevel? level,
    $core.String? summary,
    DmarcStatus? dmarc,
    $core.Iterable<StatusCheck>? checks,
  }) {
    final $result = create();
    if (domain != null) {
      $result.domain = domain;
    }
    if (usedBy != null) {
      $result.usedBy.addAll(usedBy);
    }
    if (level != null) {
      $result.level = level;
    }
    if (summary != null) {
      $result.summary = summary;
    }
    if (dmarc != null) {
      $result.dmarc = dmarc;
    }
    if (checks != null) {
      $result.checks.addAll(checks);
    }
    return $result;
  }
  EmailDomainStatus._() : super();
  factory EmailDomainStatus.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EmailDomainStatus.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EmailDomainStatus', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'domain')
    ..pPS(2, _omitFieldNames ? '' : 'usedBy')
    ..e<StatusLevel>(3, _omitFieldNames ? '' : 'level', $pb.PbFieldType.OE, defaultOrMaker: StatusLevel.STATUS_LEVEL_UNKNOWN, valueOf: StatusLevel.valueOf, enumValues: StatusLevel.values)
    ..aOS(4, _omitFieldNames ? '' : 'summary')
    ..aOM<DmarcStatus>(5, _omitFieldNames ? '' : 'dmarc', subBuilder: DmarcStatus.create)
    ..pc<StatusCheck>(6, _omitFieldNames ? '' : 'checks', $pb.PbFieldType.PM, subBuilder: StatusCheck.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EmailDomainStatus clone() => EmailDomainStatus()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EmailDomainStatus copyWith(void Function(EmailDomainStatus) updates) => super.copyWith((message) => updates(message as EmailDomainStatus)) as EmailDomainStatus;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EmailDomainStatus create() => EmailDomainStatus._();
  EmailDomainStatus createEmptyInstance() => create();
  static $pb.PbList<EmailDomainStatus> createRepeated() => $pb.PbList<EmailDomainStatus>();
  @$core.pragma('dart2js:noInline')
  static EmailDomainStatus getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EmailDomainStatus>(create);
  static EmailDomainStatus? _defaultInstance;

  /// The domain, e.g. `example.com` (the domain of the `from_address` the providers send as).
  @$pb.TagNumber(1)
  $core.String get domain => $_getSZ(0);
  @$pb.TagNumber(1)
  set domain($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasDomain() => $_has(0);
  @$pb.TagNumber(1)
  void clearDomain() => clearField(1);

  /// Names of the providers (see `ProviderStatus.provider`) that send from this domain.
  @$pb.TagNumber(2)
  $core.List<$core.String> get usedBy => $_getList(1);

  @$pb.TagNumber(3)
  StatusLevel get level => $_getN(2);
  @$pb.TagNumber(3)
  set level(StatusLevel v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasLevel() => $_has(2);
  @$pb.TagNumber(3)
  void clearLevel() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get summary => $_getSZ(3);
  @$pb.TagNumber(4)
  set summary($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSummary() => $_has(3);
  @$pb.TagNumber(4)
  void clearSummary() => clearField(4);

  /// The domain's parsed DMARC record. Always present; `record_found` says whether one exists.
  @$pb.TagNumber(5)
  DmarcStatus get dmarc => $_getN(4);
  @$pb.TagNumber(5)
  set dmarc(DmarcStatus v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasDmarc() => $_has(4);
  @$pb.TagNumber(5)
  void clearDmarc() => clearField(5);
  @$pb.TagNumber(5)
  DmarcStatus ensureDmarc() => $_ensure(4);

  /// SPF, DKIM, MX, ... checks -- DNS lookups plus provider-reported verification state.
  @$pb.TagNumber(6)
  $core.List<StatusCheck> get checks => $_getList(5);
}

/// A parsed DMARC record (`_dmarc.<domain>` TXT) -- RFC 7489 tags in friendly form.
class DmarcStatus extends $pb.GeneratedMessage {
  factory DmarcStatus({
    $core.bool? recordFound,
    $core.String? rawRecord,
    $core.String? policy,
    $core.String? subdomainPolicy,
    $core.int? percentage,
    $core.Iterable<$core.String>? aggregateReportUris,
    $core.Iterable<$core.String>? forensicReportUris,
    $core.String? dkimAlignment,
    $core.String? spfAlignment,
    StatusLevel? level,
    $core.String? summary,
  }) {
    final $result = create();
    if (recordFound != null) {
      $result.recordFound = recordFound;
    }
    if (rawRecord != null) {
      $result.rawRecord = rawRecord;
    }
    if (policy != null) {
      $result.policy = policy;
    }
    if (subdomainPolicy != null) {
      $result.subdomainPolicy = subdomainPolicy;
    }
    if (percentage != null) {
      $result.percentage = percentage;
    }
    if (aggregateReportUris != null) {
      $result.aggregateReportUris.addAll(aggregateReportUris);
    }
    if (forensicReportUris != null) {
      $result.forensicReportUris.addAll(forensicReportUris);
    }
    if (dkimAlignment != null) {
      $result.dkimAlignment = dkimAlignment;
    }
    if (spfAlignment != null) {
      $result.spfAlignment = spfAlignment;
    }
    if (level != null) {
      $result.level = level;
    }
    if (summary != null) {
      $result.summary = summary;
    }
    return $result;
  }
  DmarcStatus._() : super();
  factory DmarcStatus.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory DmarcStatus.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'DmarcStatus', package: const $pb.PackageName(_omitMessageNames ? '' : 'rellm'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'recordFound')
    ..aOS(2, _omitFieldNames ? '' : 'rawRecord')
    ..aOS(3, _omitFieldNames ? '' : 'policy')
    ..aOS(4, _omitFieldNames ? '' : 'subdomainPolicy')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'percentage', $pb.PbFieldType.O3)
    ..pPS(6, _omitFieldNames ? '' : 'aggregateReportUris')
    ..pPS(7, _omitFieldNames ? '' : 'forensicReportUris')
    ..aOS(8, _omitFieldNames ? '' : 'dkimAlignment')
    ..aOS(9, _omitFieldNames ? '' : 'spfAlignment')
    ..e<StatusLevel>(10, _omitFieldNames ? '' : 'level', $pb.PbFieldType.OE, defaultOrMaker: StatusLevel.STATUS_LEVEL_UNKNOWN, valueOf: StatusLevel.valueOf, enumValues: StatusLevel.values)
    ..aOS(11, _omitFieldNames ? '' : 'summary')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  DmarcStatus clone() => DmarcStatus()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  DmarcStatus copyWith(void Function(DmarcStatus) updates) => super.copyWith((message) => updates(message as DmarcStatus)) as DmarcStatus;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DmarcStatus create() => DmarcStatus._();
  DmarcStatus createEmptyInstance() => create();
  static $pb.PbList<DmarcStatus> createRepeated() => $pb.PbList<DmarcStatus>();
  @$core.pragma('dart2js:noInline')
  static DmarcStatus getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DmarcStatus>(create);
  static DmarcStatus? _defaultInstance;

  /// Whether a `v=DMARC1` TXT record exists at `_dmarc.<domain>`.
  @$pb.TagNumber(1)
  $core.bool get recordFound => $_getBF(0);
  @$pb.TagNumber(1)
  set recordFound($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRecordFound() => $_has(0);
  @$pb.TagNumber(1)
  void clearRecordFound() => clearField(1);

  /// The raw record, e.g. `v=DMARC1; p=reject; rua=mailto:dmarc@example.com`. Empty if none.
  @$pb.TagNumber(2)
  $core.String get rawRecord => $_getSZ(1);
  @$pb.TagNumber(2)
  set rawRecord($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRawRecord() => $_has(1);
  @$pb.TagNumber(2)
  void clearRawRecord() => clearField(2);

  /// Requested handling for failing mail (`p=`): `none` (monitor only), `quarantine` or `reject`.
  /// Empty if no record.
  @$pb.TagNumber(3)
  $core.String get policy => $_getSZ(2);
  @$pb.TagNumber(3)
  set policy($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPolicy() => $_has(2);
  @$pb.TagNumber(3)
  void clearPolicy() => clearField(3);

  /// Policy for subdomains (`sp=`); empty means "same as `policy`".
  @$pb.TagNumber(4)
  $core.String get subdomainPolicy => $_getSZ(3);
  @$pb.TagNumber(4)
  set subdomainPolicy($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSubdomainPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearSubdomainPolicy() => clearField(4);

  /// Percentage of failing mail the policy applies to (`pct=`, default 100).
  @$pb.TagNumber(5)
  $core.int get percentage => $_getIZ(4);
  @$pb.TagNumber(5)
  set percentage($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPercentage() => $_has(4);
  @$pb.TagNumber(5)
  void clearPercentage() => clearField(5);

  /// Where aggregate reports are sent (`rua=`).
  @$pb.TagNumber(6)
  $core.List<$core.String> get aggregateReportUris => $_getList(5);

  /// Where forensic reports are sent (`ruf=`).
  @$pb.TagNumber(7)
  $core.List<$core.String> get forensicReportUris => $_getList(6);

  /// DKIM alignment (`adkim=`): `relaxed` (default) or `strict`.
  @$pb.TagNumber(8)
  $core.String get dkimAlignment => $_getSZ(7);
  @$pb.TagNumber(8)
  set dkimAlignment($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasDkimAlignment() => $_has(7);
  @$pb.TagNumber(8)
  void clearDkimAlignment() => clearField(8);

  /// SPF alignment (`aspf=`): `relaxed` (default) or `strict`.
  @$pb.TagNumber(9)
  $core.String get spfAlignment => $_getSZ(8);
  @$pb.TagNumber(9)
  set spfAlignment($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasSpfAlignment() => $_has(8);
  @$pb.TagNumber(9)
  void clearSpfAlignment() => clearField(9);

  @$pb.TagNumber(10)
  StatusLevel get level => $_getN(9);
  @$pb.TagNumber(10)
  set level(StatusLevel v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasLevel() => $_has(9);
  @$pb.TagNumber(10)
  void clearLevel() => clearField(10);

  /// One friendly sentence, e.g. "Enforced (reject) for 100% of failing mail."
  @$pb.TagNumber(11)
  $core.String get summary => $_getSZ(10);
  @$pb.TagNumber(11)
  set summary($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasSummary() => $_has(10);
  @$pb.TagNumber(11)
  void clearSummary() => clearField(11);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
