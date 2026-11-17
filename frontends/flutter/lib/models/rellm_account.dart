import 'dart:convert';

import 'package:rellm/models/rellm_server.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../app_state.dart';
import '../generated/authentication.pb.dart';
import '../generated/rellm.pbgrpc.dart';
import '../generated/permissions.pbenum.dart';
import '../generated/users.pb.dart';
import 'rellm_clients.dart';
import 'server_errors.dart';
import 'storage.dart';

const uuid = Uuid();

/// Local storage for the user's account on a given Rellm instance.
/// Constructors are private; factory methods [loginToAccount] and [createAccount]
/// should be used instead.
class RellmAccount {
  static final log = Logger('RellmAccount');
  static bool get loggedIn => _selectedAccount != null;
  static RellmAccount? _selectedAccount;
  static RellmAccount? get selectedAccount => _selectedAccount;
  static set selectedAccount(RellmAccount? account) {
    _selectedAccount = account;
    if (account != null) {
      appStorage.setString('selected_account', account.id);
    } else {
      appStorage.remove('selected_account');
    }
  }

  // static String get selectedServer =>
  //     selectedAccount?.server ?? _selectedServer;

  // static const String _selectedServer = defaultServer;

  static Future<RellmAccount?> loginToAccount(String server, String username,
      String password, Function(String) showMessage,
      {bool allowInsecure = false, bool selectAccount = true}) async {
    return _authAccount(
        (client) => client.login(LoginRequest(
            usernamePassword: UsernamePasswordLoginRequest(
                username: username, password: password))),
        ['Logging in', 'login', 'Logged in'],
        server,
        username,
        password,
        showMessage,
        allowInsecure: allowInsecure,
        selectAccount: selectAccount);
    // RellmClient? client = await RellmClients.createAndTestClient(server,
    //     showMessage: showMessage, allowInsecure: allowInsecure);
    // if (client == null) return null;
    // await communicationDelay;

    // RefreshTokenResponse authResponse;
    // try {
    //   authResponse = await client
    //       .login(LoginRequest(username: username, password: password));
    // } catch (e) {
    //   await communicationDelay;
    //   showMessage("Failed to login to $server as \"$username\"!");
    //   final formattedError = formatServerError(e);
    //   showMessage(formattedError);
    //   return null;
    // }
    // await communicationDelay;
    // showMessage("Logged in to $server as $username!");

    // final account = RellmAccount._fromAuth(server,
    //     authResponse.refreshToken.token, authResponse.accessToken.token, username,
    //     allowInsecure: allowInsecure);
    // await account.saveNew(atBeginning: selectAccount);
    // if (selectAccount) {
    //   RellmAccount.selectedAccount = account;
    //   RellmServer.selectedServer =
    //       (await RellmServer.servers).firstWhere((s) => s.server == server);
    //   await RellmServer.selectedServer.updateConfiguration();
    //   await RellmServer.selectedServer.save();
    // }
    // return account;
  }

  static Future<RellmAccount?> createAccount(String server, String username,
      String password, Function(String) showMessage,
      {bool allowInsecure = false, bool selectAccount = true}) async {
    return _authAccount(
        (client) => client.createAccount(CreateAccountRequest()
          ..username = username
          ..password = password),
        ['Creating account', 'create account', 'Created account'],
        server,
        username,
        password,
        showMessage,
        allowInsecure: allowInsecure,
        selectAccount: selectAccount);
  }

  static Future<RellmAccount?> _authAccount(
      Future<RefreshTokenResponse> Function(RellmClient) authenticator,
      List<String> verbs,
      String server,
      String username,
      String password,
      Function(String) showMessage,
      {bool allowInsecure = false,
      bool selectAccount = true}) async {
    RellmClient? client = await RellmClients.createAndTestClient(server,
        showMessage: showMessage, allowInsecure: allowInsecure);
    if (client == null) return null;
    if (selectAccount) {
      await communicationDelay;
    }
    // showMessage("Connected to $server! ${verbs[0]}...");
    RefreshTokenResponse authResponse;
    try {
      authResponse = await authenticator(client);
    } catch (e) {
      if (selectAccount) {
        await communicationDelay;
      }
      showMessage("Failed to ${verbs[1]} $username on $server!");
      final formattedError = formatServerError(e);
      showMessage(formattedError);
      return null;
    }
    await communicationDelay;
    showMessage("${verbs[2]} $username on $server!");

    final account = RellmAccount._fromAuth(
        server, authResponse.refreshToken.token, authResponse.accessToken.token,
        allowInsecure: allowInsecure);
    await account.saveNew(atBeginning: selectAccount);
    if (selectAccount) {
      RellmAccount.selectedAccount = account;
      RellmServer.selectedServer =
          (await RellmServer.servers).firstWhere((s) => s.server == server);
      await RellmServer.selectedServer.updateConfiguration();
      await RellmServer.selectedServer.save();
    }
    return account;
  }

  final String id;
  final String server;
  final String authorizationToken;
  String serviceVersion;
  String accessToken;
  int accessTokenExpiresAt;
  bool allowInsecure;
  User? user;
  String get userId => user?.id ?? '';
  String get username => user?.username ?? '';
  List<Permission> get permissions => user?.permissions ?? [];

  /// Used by [loginToAccount] and [createAccount] when creating a new account.
  RellmAccount._fromAuth(
      this.server, this.authorizationToken, this.accessToken,
      {this.allowInsecure = false})
      : id = uuid.v4(),
        // userId = "",
        serviceVersion = "",
        accessTokenExpiresAt = 0; //permissions = [];

  /// Used by [accounts] to load data.
  RellmAccount._fromJson(Map<String, dynamic> json)
      : id = json['id'],
        // username = json['username'] ?? '',
        // userId = json['userId'] ?? '',
        server = json['server'],
        authorizationToken = json['authorizationToken'],
        accessToken = json['accessToken'],
        allowInsecure = json['allowInsecure'],
        serviceVersion = json['serviceVersion'] ?? "",
        accessTokenExpiresAt = json['accessTokenExpiresAt'] ?? 0,
        // permissions = json['permissions'] == null
        //     ? []
        //     : (json['permissions'] as List<dynamic>)
        //         .map((e) => Permission.values.firstWhere((p) => p.name == e,
        //             orElse: () => Permission.PERMISSION_UNKNOWN))
        //         .where((e) => e != Permission.PERMISSION_UNKNOWN)
        //         .toList(),
        user = json['user'] == null
            ? null
            : _userFromJson(jsonEncode(json['user']));

  static User? _userFromJson(String json) {
    try {
      return User.fromJson(json);
    } catch (e) {
      log.severe(e);
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        // 'username': username,
        // 'userId': userId,
        'server': server,
        'authorizationToken': authorizationToken,
        'accessToken': accessToken,
        'accessTokenExpiresAt': accessTokenExpiresAt,
        'allowInsecure': allowInsecure,
        'serviceVersion': serviceVersion,
        // 'permissions': permissions.map((e) => e.name).toList(),
        'user': user == null ? null : jsonDecode(user!.writeToJson()),
      };

  Future<void> save() async {
    List<RellmAccount> jsonArray = await accounts;
    final index = jsonArray.indexWhere((element) => element.id == id);
    if (index == -1) {
      jsonArray.add(this);
    } else {
      jsonArray[index] = this;
    }
    await updateAccountList(jsonArray);
  }

  Future<void> saveNew({bool atBeginning = true}) async {
    List<RellmAccount> jsonArray = await accounts;
    jsonArray.insert(atBeginning ? 0 : jsonArray.length, this);
    await updateAccountList(jsonArray);
  }

  Future<void> delete() async {
    List<RellmAccount> jsonArray = await accounts;
    jsonArray.removeWhere((e) => e.id == id);
    await updateAccountList(jsonArray);
  }

  static Future<bool?> updateAccountList(List<RellmAccount> accounts) async {
    if (!accounts.any((a) => a.id == selectedAccount?.id)) {
      appStorage.remove('selected_account');
      selectedAccount = null;
    }
    return appStorage.setStringList(
        'rellm_accounts', accounts.map((e) => jsonEncode(e)).toList());
  }

  static Future<List<RellmAccount>> get accounts async {
    List<String> jsonArrayString =
        appStorage.getStringList('rellm_accounts') ?? [];
    final accountsJson = jsonArrayString
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();
    // List<Map<String, dynamic>> jsonArray = await accountsJson;
    final accounts = accountsJson
        .map((e) {
          try {
            return RellmAccount._fromJson(e);
          } catch (e) {
            // print(e);
            return null;
          }
        })
        .where((e) => e != null)
        .toList()
        .cast<RellmAccount>();

    if (selectedAccount != null) {
      selectedAccount = accounts.firstWhere((a) => a.id == selectedAccount?.id,
          orElse: () => selectedAccount!);
    }
    return accounts;
  }
}
