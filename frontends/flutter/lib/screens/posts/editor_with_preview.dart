import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rellm/rellm_state.dart';

import '../../app_state.dart';
import '../../generated/media.pb.dart';
import '../../generated/posts.pb.dart';
import '../../models/rellm_account.dart';
import '../../models/rellm_server.dart';
import 'post_preview.dart';

class EditorWithPreview extends StatefulWidget {
  // If not provided, will hide the title.
  final TextEditingController? titleController;
  final TextEditingController? linkController;
  final TextEditingController? contentController;
  final ValueNotifier<bool>? enabled;
  final Widget Function()? buildPreview;

  const EditorWithPreview(
      {Key? key,
      this.titleController,
      this.linkController,
      this.contentController,
      this.enabled,
      this.buildPreview})
      : super(key: key);

  @override
  EditorWithPreviewState createState() => EditorWithPreviewState();
}

class EditorWithPreviewState extends RellmState<EditorWithPreview> {
  List<bool> focuses = [false, false, false];
  bool get inlinePreview => mq.size.width > 600;
  bool _showPreview = false;
  bool get showPreview => _showPreview && !inlinePreview;
  set showPreview(bool value) {
    if (value != _showPreview) {
      final focusSources = [titleFocus, linkFocus, contentFocus];
      if (value == true) {
        focuses = focusSources.map((e) => e.hasFocus).toList();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          focuses.asMap().forEach((index, hasFocus) {
            if (hasFocus) {
              focusSources[index].requestFocus();
            }
          });
        });
      }

      setState(() {
        _showPreview = value;
      });
    }
  }

  bool quickPasteDone = false;

  final FocusNode titleFocus = FocusNode();
  final FocusNode linkFocus = FocusNode();
  final FocusNode contentFocus = FocusNode();
  late final TextEditingController? titleController;
  late final TextEditingController? linkController;
  late final TextEditingController? contentController;
  String? get title => titleController?.value.text;
  String? get link => linkController?.value.text;
  String? get content => contentController?.value.text;
  bool get linkValid {
    try {
      Uri.parse(link!);
      return true;
    } catch (e) {
      return false;
    }
  }

  bool get canCreate =>
      title?.isNotEmpty == true ||
      (link?.isNotEmpty == true && linkValid) ||
      content?.isNotEmpty == true;

  late final ValueNotifier<bool> enabled;

  @override
  void initState() {
    super.initState();
    titleController = widget.titleController;
    linkController = widget.linkController;
    contentController = widget.contentController;
    enabled = widget.enabled ?? ValueNotifier(true);

    titleController?.addListener(() {
      setState(() {});
    });
    contentController?.addListener(() {
      setState(() {});
    });
    linkController?.addListener(() {
      setState(() {});
    });
  }

  @override
  dispose() {
    titleFocus.dispose();
    contentFocus.dispose();
    linkFocus.dispose();
    // if (widget.titleController == null) titleController.dispose();
    // if (widget.contentController == null) contentController.dispose();
    // if (widget.linkController == null) linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxWidth: 500),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                if (!inlinePreview) buildModeSwitch(context),
                const SizedBox(height: 8),
                Expanded(
                    child: Stack(
                  children: [
                    IgnorePointer(
                      ignoring: showPreview,
                      child: AnimatedOpacity(
                          duration: animationDuration,
                          opacity: showPreview ? 0.03 : 1,
                          child: buildEditor(context)),
                    ),
                    if (!inlinePreview)
                      IgnorePointer(
                        ignoring: !showPreview,
                        child: AnimatedOpacity(
                            duration: animationDuration,
                            opacity: !showPreview ? 0 : 1,
                            child: buildPreview(context)),
                      )
                  ],
                )),
              ],
            ),
          ),
          if (inlinePreview) SizedBox(width: 300, child: buildPreview(context))
        ],
      ),
    );
  }

  Widget buildModeSwitch(BuildContext context) {
    return Card(
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: TextButton(
              onPressed: () {
                showPreview = false;
              },
              style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                      !showPreview ? Colors.white : Colors.transparent)),
              // doingStuff || username.isEmpty || password.isEmpty
              //     ? null
              //     : createAccount,
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Column(
                  children: [
                    Text('EDIT'),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: TextButton(
              onPressed: () {
                showPreview = true;
              },
              style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(
                      showPreview ? Colors.white : Colors.transparent)),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Column(
                  children: [
                    Text('PREVIEW'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPreview(BuildContext context) {
    String? content, link;
    if (this.content?.isNotEmpty == true) content = this.content;
    if (this.link?.isNotEmpty == true) link = this.link;
    if (MediaQuery.of(context).size.height < 552) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: PostPreview(
                  allowScrollingContent: true,
                  server: RellmServer.selectedServer.server,
                  maxContentHeight: mq.size.height - 200,
                  post: Post()
                    ..title = title!
                    ..content = content!
                    ..link = link!
                    ..author = (Author()
                      ..username = RellmAccount.selectedAccount?.username ??
                          "jonline.io/jon")),
            ),
          ),
        ],
      );
    } else {
      return Column(children: [
        const Expanded(
          child: SizedBox(),
        ),
        PostPreview(
            allowScrollingContent: true,
            server: RellmServer.selectedServer.server,
            maxContentHeight: mq.size.height - 200,
            post: Post()
              ..title = title!
              ..content = content!
              ..link = link!
              ..author = (Author()
                ..username = RellmAccount.selectedAccount?.username ??
                    "jonline.io/jon")),
        const Expanded(
          child: SizedBox(),
        ),
      ]);
    }
  }

  Widget buildEditor(BuildContext context) {
    return Column(children: [
      if (widget.titleController != null)
        TextField(
          focusNode: titleFocus,
          controller: titleController,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          enableSuggestions: true,
          autocorrect: true,
          maxLines: 1,
          cursorColor: Colors.white,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w400, fontSize: 14),
          enabled: enabled.value && !showPreview,
          decoration: const InputDecoration(
              border: InputBorder.none, hintText: "Title", isDense: true),
          onChanged: (value) {},
        ),
      if (widget.linkController != null)
        Row(
          children: [
            Expanded(
              child: TextField(
                focusNode: linkFocus,
                controller: linkController,
                keyboardType: TextInputType.url,
                enableSuggestions: false,
                autocorrect: false,
                maxLines: 1,
                cursorColor: Colors.white,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    fontSize: 14),
                enabled: enabled.value && !showPreview,
                decoration: const InputDecoration(
                    border: InputBorder.none, hintText: "Link", isDense: true),
                onChanged: (value) {},
              ),
            ),
            AnimatedContainer(
                duration: animationDuration,
                width: 72,
                child: TextButton(
                  onPressed: quickPasteDone
                      ? null
                      : () async {
                          final String? text =
                              (await Clipboard.getData(Clipboard.kTextPlain))
                                  ?.text;
                          if (text == null || !text.startsWith("http")) {
                            showSnackBar('No link found in the clipboard. 😔');
                          } else {
                            setState(() {
                              linkController?.text = text;
                              quickPasteDone = true;
                            });
                            Future.delayed(const Duration(seconds: 1), () {
                              setState(() {
                                quickPasteDone = false;
                              });
                            });
                          }
                        },
                  child: Stack(
                    children: [
                      AnimatedOpacity(
                          opacity: quickPasteDone ? 0.8 : 1,
                          duration: animationDuration,
                          child:
                              Icon(Icons.paste, color: appState.primaryColor)),
                      AnimatedOpacity(
                          opacity: quickPasteDone ? 1 : 0,
                          duration: animationDuration,
                          child: Icon(Icons.check, color: appState.navColor)),
                    ],
                  ),
                ))
          ],
        ),
      const SizedBox(height: 8),
      if (widget.contentController != null)
        Expanded(
          child: TextField(
            focusNode: contentFocus,
            controller: contentController,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            enableSuggestions: true,
            autocorrect: true,
            maxLines: null,
            cursorColor: Colors.white,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w400, fontSize: 14),
            enabled: enabled.value && !showPreview,
            decoration: const InputDecoration(
                border: InputBorder.none, hintText: "Content", isDense: true),
            onChanged: (value) {},
          ),
        ),
      const Align(
          alignment: Alignment.centerRight,
          child: Text(
            "Markdown content is supported.",
            textAlign: TextAlign.right,
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w400, fontSize: 12),
          )),
    ]);
  }

  showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
    ));
  }
}
