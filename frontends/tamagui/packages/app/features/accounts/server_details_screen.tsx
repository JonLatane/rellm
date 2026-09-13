import { ExternalCDNConfig, Media, Permission, ServerConfiguration, ServerInfo, UserListingType, WebUserInterface } from '@rellm/api';
import { Anchor, AnimatePresence, Button, Card, Heading, Input, Label, Paragraph, ScrollView, Spinner, Switch, Text, TextArea, XStack, YStack, ZStack, formatError, isWeb, standardAnimation, useToastController, useWindowDimensions } from '@rellm/ui';
import { Binary, CheckCircle, ChevronDown, ChevronRight, ChevronUp, Code, Cog, Container, Delete, Github, Heart, Info, Network, Palette, TabletSmartphone } from '@tamagui/lucide-icons';
import { AutoAnimatedList, PermissionsEditor, PermissionsEditorProps, SubnavButton, TamaguiMarkdown, WebUserInterfacePicker } from 'app/components';
import { colorMeta, useAppDispatch, useFederatedAccountOrServer, usePaginatedRendering, useUsersPage } from 'app/hooks';
import { RellmServer, RootState, federatedId, getCachedServerClient, getConfiguredServerClient, getCredentialClient, getServerClient, selectServerById, serverID, upsertServer, useRootSelector, useServerTheme } from 'app/store';
import { hasAdminPermission, setDocumentTitle, themedButtonBackground } from 'app/utils';
import React, { useEffect, useState } from 'react';
import { HexColorPicker } from "react-colorful";
import { createParam } from 'solito';
import { useLink } from 'solito/link';
import { MediaRenderer } from '../media/media_renderer';
import { AppSection } from '../navigation/features_navigation';
import { ServerNameAndLogo } from '../navigation/server_name_and_logo';
import { TabsNavigation } from '../navigation/tabs_navigation';
import { RecommendedServer } from './recommended_server';
import ServerCard from './server_card';
import { SingleMediaChooser } from './single_media_chooser';
import { AccountOrServerContextProvider, MediaRef } from 'app/contexts';
import { PageChooser } from '../home/page_chooser';
import { UserCard } from '../user/user_card';

const { useParam } = createParam<{ id: string, section?: string }>()

export function ServerDetailsScreen() {
  return BaseServerDetailsScreen();
}

const configurableUserPermissions = [
  Permission.VIEW_USERS,
  Permission.PUBLISH_USERS_LOCALLY,
  Permission.PUBLISH_USERS_GLOBALLY,
  Permission.VIEW_GROUPS,
  Permission.CREATE_GROUPS,
  Permission.VIEW_MEDIA,
  Permission.CREATE_MEDIA,
  Permission.PUBLISH_MEDIA_LOCALLY,
  Permission.PUBLISH_MEDIA_GLOBALLY,
  Permission.PUBLISH_GROUPS_LOCALLY,
  Permission.PUBLISH_GROUPS_GLOBALLY,
  Permission.JOIN_GROUPS,
  Permission.VIEW_POSTS,
  Permission.CREATE_POSTS,
  Permission.PUBLISH_POSTS_LOCALLY,
  Permission.PUBLISH_POSTS_GLOBALLY,
  Permission.VIEW_EVENTS,
  Permission.CREATE_EVENTS,
  Permission.RSVP_TO_EVENTS,
  Permission.PUBLISH_EVENTS_LOCALLY,
  Permission.PUBLISH_EVENTS_GLOBALLY,
  Permission.SYNC_EVENTS_FROM_ICS,
  Permission.SYNC_POSTS_FROM_RSS,
  Permission.SYNC_POSTS_FROM_ATOM,
];

export function BaseServerDetailsScreen(specificServer?: string) {
  const [requestedServerUrl] = specificServer ? [specificServer] : useParam('id');
  const requestedServerUrlParts = requestedServerUrl?.split(':');
  const requestedServerUrlValid = requestedServerUrlParts?.length == 2
    && ['http', 'https'].includes(requestedServerUrlParts[0]!);
  // console.log('BaseServerDetailsScreen', {
  //   requestedServerUrl,
  //   requestedServerUrlParts,
  //   requestedServerUrlValid,
  // })
  const requestedServer: RellmServer | undefined = requestedServerUrlParts
    ? {
      host: requestedServerUrlParts[1]!,
      secure: requestedServerUrlParts[0]! == 'https',
    } : undefined;
  // console.log('BaseServerDetailsScreen', {
  //   requestedServerUrl,
  //   requestedServerUrlParts,
  //   requestedServerUrlValid,
  //   requestedServer
  // })
  const dispatch = useAppDispatch();
  const app = useRootSelector((state: RootState) => state.config);
  const savedServer: RellmServer | undefined = useRootSelector((state: RootState) =>
    selectServerById(state.servers, requestedServerUrl!));
  const unsavedServer: RellmServer | undefined = requestedServer
    ? getCachedServerClient(requestedServer)
    : undefined;
  useEffect(() => {
    if (!unsavedServer && requestedServer) getConfiguredServerClient(requestedServer);
  }, [unsavedServer, requestedServer]);

  const server = savedServer ?? unsavedServer;

  const accountOrServer = useFederatedAccountOrServer(server?.host);
  const { account, server: selectedServer } = accountOrServer;
  //useAccountOrServer();
  const serverIsSelected = server && selectedServer &&
    serverID(server) == serverID(selectedServer);
  const isAdmin = !!account && !!server &&
    serverID(account.server) == serverID(server) &&
    hasAdminPermission(account?.user);
  // console.log('isAdmin', isAdmin, account, server);
  const [updating, setUpdating] = useState(false);
  const [updated, setUpdated] = useState(false);
  const [updateError, setUpdateError] = useState('');
  const aboutRellmLink = useLink({ href: '/about_rellm' })

  const { serviceVersion, serverConfiguration } = server || {};
  const [_, githubVersion] = serviceVersion?.version?.split('-') ?? [];
  const githubLink = useLink({ href: `https://github.com/JonLatane/rellm/commit/${githubVersion}` });
  const protocolDocsLink = useLink({ href: `http://${server?.host}/docs/protocol` });
  const flutterUiLink = useLink({ href: `http://${server?.host}/flutter#/accounts/server/${server?.host}/configuration` });

  const serverName = serverConfiguration?.serverInfo?.name;
  const [name, setName] = useState(serverName || undefined);
  // if (serverName && name != serverName && name == undefined) {
  //   setName(serverName);
  // }

  useEffect(() => {
    setDocumentTitle(`About ${specificServer ? 'Community' : 'Server'}${serverName && serverName != '' ? ` | ${serverName}` : ''}`)
  }, [specificServer, serverName, window.location.search]);

  const serverDescription = serverConfiguration?.serverInfo?.description;
  const [description, setDescription] = useState(serverDescription || undefined);
  // if (serverDescription && description != serverDescription && description == undefined) {
  //   setDescription(serverDescription);
  // }
  const serverPrivacyPolicy = serverConfiguration?.serverInfo?.privacyPolicy;
  const [privacyPolicy, setPrivacyPolicy] = useState(serverPrivacyPolicy);
  const serverMediaPolicy = serverConfiguration?.serverInfo?.mediaPolicy;
  const [mediaPolicy, setMediaPolicy] = useState(serverMediaPolicy);
  const serverLogo = serverConfiguration?.serverInfo?.logo;
  const [logo, setLogo] = useState(serverLogo || undefined);

  const serverWebUserInterface = serverConfiguration?.serverInfo?.webUserInterface ?? WebUserInterface.REACT_TAMAGUI;
  const [webUserInterface, setWebUserInterface] = useState(serverWebUserInterface);

  const serverExternalCdnConfig = serverConfiguration?.externalCdnConfig;
  const [externalCdnConfig, setExternalCdnConfig] = useState(serverExternalCdnConfig);

  const serverRecommendedHosts = serverConfiguration?.serverInfo?.recommendedServerHosts;
  const serverFederatedServers = serverConfiguration?.federationInfo?.servers?.length ?? 0 > 0
    ? serverConfiguration?.federationInfo?.servers
    : serverRecommendedHosts?.map(host => ({ host, configuredByDefault: true, pinnedByDefault: true }));
  // console.log('serverFederatedServers', serverFederatedServers);
  const [federatedServers, setFederatedServers] = useState(serverFederatedServers);
  const [newRecommendedHostName, setNewRecommendedHostName] = useState('');
  const isNewRecommendedHostNameValid = /^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/.test(newRecommendedHostName)
    && !federatedServers?.some(s => s.host === newRecommendedHostName)
    && server?.host !== newRecommendedHostName;
  // if (defaultClientDomain && name != serverName && name == undefined) {
  //   setName(serverName);
  // }

  const [showVersionInfo, setShowVersionInfo] = useState(false);
  const primaryColorInt = serverConfiguration?.serverInfo?.colors?.primary ?? 0x424242;
  const primaryColor = `#${primaryColorInt.toString(16).slice(-6)}`;
  const [primaryColorHex, setPrimaryColorHex] = useState(primaryColor);
  const primaryColorValid = /^#[0-9A-Fa-f]{6}$/i.test(primaryColorHex);

  // if (primaryColorHex != primaryColor && primaryColorHex == '#424242') {
  //   setPrimaryColorHex(primaryColor);
  // }

  const navColorInt = serverConfiguration?.serverInfo?.colors?.navigation ?? 0xFFFFFF;
  const navColor = `#${navColorInt.toString(16).slice(-6)}`;
  const [navColorHex, setNavColorHex] = useState(navColor);
  const navColorValid = /^#[0-9A-Fa-f]{6}$/i.test(navColorHex);

  const { textColor: primaryTextColor } = colorMeta(primaryColor);
  const { textColor: navTextColor } = colorMeta(navColor);
  const { primaryAnchorColor, navAnchorColor, warningAnchorColor } = useServerTheme();

  const serverDefaultPermissions = serverConfiguration?.defaultUserPermissions ?? [];
  const serverAnonymousPermissions = serverConfiguration?.anonymousUserPermissions ?? [];
  const serverBasicPermissions = serverConfiguration?.basicUserPermissions ?? [];
  const [defaultPermissions, setDefaultPermissions] = useState(serverDefaultPermissions);
  const [anonymousPermissions, setAnonymousPermissions] = useState(serverAnonymousPermissions);
  const [basicPermissions, setBasicPermissions] = useState(serverBasicPermissions);

  const inputsValid = primaryColorValid && navColorValid;


  useEffect(() => {
    setName(serverName);
    setDescription(serverDescription);
    setPrivacyPolicy(serverPrivacyPolicy);
    setLogo(serverLogo);
    setWebUserInterface(serverWebUserInterface);
    setExternalCdnConfig(serverExternalCdnConfig);
    setDefaultPermissions(serverDefaultPermissions);
    setAnonymousPermissions(serverAnonymousPermissions);
    setBasicPermissions(serverBasicPermissions);
    setPrimaryColorHex(primaryColor);
    setNavColorHex(navColor);
    // setRecommendedHosts(serverRecommendedHosts);
    setFederatedServers(serverFederatedServers);

  }, [serverConfiguration]);

  function selectDefaultPermission(permission: Permission, permissionSet: Permission[], setPermissionSet: (permissions: Permission[]) => void) {
    if (permissionSet.includes(permission)) {
      setPermissionSet(permissionSet.filter(p => p != permission));
    } else {
      setPermissionSet([...permissionSet, permission]);
    }
  }
  function deselectDefaultPermission(permission: Permission, permissionSet: Permission[], setPermissionSet: (permissions: Permission[]) => void) {
    setPermissionSet(permissionSet.filter(p => p != permission));
  }
  const defaultPermissionsEditorProps: PermissionsEditorProps = {
    selectablePermissions: configurableUserPermissions,
    selectedPermissions: defaultPermissions,
    selectPermission: (p) => selectDefaultPermission(p, defaultPermissions, setDefaultPermissions),
    deselectPermission: (p) => deselectDefaultPermission(p, defaultPermissions, setDefaultPermissions),
    editMode: isAdmin ?? false
  };
  const anonymousPermissionsEditorProps: PermissionsEditorProps = {
    selectablePermissions: configurableUserPermissions,
    selectedPermissions: anonymousPermissions,
    selectPermission: (p) => selectDefaultPermission(p, anonymousPermissions, setAnonymousPermissions),
    deselectPermission: (p) => deselectDefaultPermission(p, anonymousPermissions, setAnonymousPermissions),
    editMode: isAdmin ?? false
  };
  const basicPermissionsEditorProps: PermissionsEditorProps = {
    selectablePermissions: configurableUserPermissions,
    selectedPermissions: basicPermissions,
    selectPermission: (p) => selectDefaultPermission(p, basicPermissions, setBasicPermissions),
    deselectPermission: (p) => deselectDefaultPermission(p, basicPermissions, setBasicPermissions),
    editMode: isAdmin ?? false
  };

  let newPrimaryColorInt = parseInt(primaryColorHex.slice(1), 16) + 0xFF000000;
  let newNavColorInt = parseInt(navColorHex.slice(1), 16) + 0xFF000000;
  let updatedConfiguration: ServerConfiguration = {
    ...serverConfiguration!,
    serverInfo: {
      ...ServerInfo.create(serverConfiguration?.serverInfo ?? {}),
      name,
      description,
      privacyPolicy,
      mediaPolicy,
      logo,
      webUserInterface,
      colors: {
        ...serverConfiguration?.serverInfo?.colors,
        primary: newPrimaryColorInt, navigation: newNavColorInt
      },
      recommendedServerHosts: federatedServers?.map(s => s.host) ?? [],
    },
    federationInfo: {
      ...serverConfiguration?.federationInfo,
      servers: federatedServers ?? [],
      mastodonServers: serverConfiguration?.federationInfo?.mastodonServers ?? [],
    },
    defaultUserPermissions: defaultPermissions,
    anonymousUserPermissions: anonymousPermissions,
    basicUserPermissions: basicPermissions,
    externalCdnConfig: externalCdnConfig
  };

  const toast = useToastController();
  async function updateServer() {
    setUpdating(true);
    setUpdated(false);
    setUpdateError('');
    //TODO: get the latest config and merge our changes into it?

    let newPrimaryColorInt = parseInt(primaryColorHex.slice(1), 16) + 0xFF000000;
    let newNavColorInt = parseInt(navColorHex.slice(1), 16) + 0xFF000000;

    let client = await getCredentialClient({ account, server: selectedServer });
    try {
      let returnedConfiguration = await client.configureServer(updatedConfiguration, client.credential);
      await dispatch(upsertServer({ ...server!, serverConfiguration: returnedConfiguration }))
        .then(() => {
          setUpdated(true);
          toast.show('Server updated.');
        })
        .then(() => setTimeout(() => setUpdated(false), 3000));
    } catch (e) {
      console.error('Error loading client', e);
      setUpdateError(formatError(e.message));
    } finally {
      setUpdating(false);
    }
  }
  const windowHeight = useWindowDimensions().height;
  const [querySection, setQuerySection] = useParam('section');
  type AboutSection = 'about' | 'theme' | 'settings' | 'federation' | 'cdn';
  const section = (querySection ?? 'about') as AboutSection;
  function sectionButton(sectionName: AboutSection, title: string, icon: React.JSX.Element) {
    return <SubnavButton title={title}
      icon={icon}
      selected={section === sectionName}
      select={() => setQuerySection(sectionName)} />;
  }
  const cloudflareLink = useLink({ href: 'https://cloudflare.com' });
  function recommendServer() {
    setFederatedServers([
      ...(federatedServers ?? []),
      { host: newRecommendedHostName.toLowerCase(), configuredByDefault: false, pinnedByDefault: false }
    ]);
    setNewRecommendedHostName('');
  }


  const adminList = useUsersPage(UserListingType.EVERYONE, 0).results.
    filter(user => user.permissions.includes(Permission.ADMIN) && user.serverHost === server?.host);
  const adminPagination = usePaginatedRendering(adminList, 10);
  const paginatedAdmins = adminPagination.results;

  return (
    <TabsNavigation appSection={AppSection.INFO}
      //onlyShowServer={server}
      primaryEntity={server ? { serverHost: server.host } : undefined}
      topChrome={
        <XStack w='100%'>
          {sectionButton('about', 'About', <Info color={section === 'about' ? navAnchorColor : undefined} />)}
          {sectionButton('theme', 'Theme', <Palette color={section === 'theme' ? navAnchorColor : undefined} />)}
          {sectionButton('settings', 'Settings', <Cog color={section === 'settings' ? navAnchorColor : undefined} />)}
          {sectionButton('federation', 'Federation', <Network color={section === 'federation' ? navAnchorColor : undefined} />)}
          {/* {sectionButton('servers', 'Servers', <Server color={section === 'servers' ? primaryAnchorColor : undefined} />)} */}
          {sectionButton('cdn', 'CDN', <Code color={section === 'cdn' ? navAnchorColor : undefined} />)}
        </XStack>
      }
      bottomChrome={server && isAdmin
        ? <XStack px='$3' w='100%' maw={800} mx='auto' opacity={.92} paddingVertical='$2'
          alignContent='center' alignItems='center' alignSelf='center'>

          <XStack f={1} />

          <ZStack w={48} h={48}>
            <YStack animation='standard' o={updated ? 1 : 0} p='$3'>
              <CheckCircle color='green' />
            </YStack>
            <YStack animation='standard' o={updating ? 1 : 0} p='$3'>
              <Spinner size='small' />
            </YStack>
          </ZStack>
          <Button maw={600} als='center'
            disabled={updating || updated || !inputsValid}
            {...themedButtonBackground(primaryColor, primaryTextColor,
              updating || updated || !inputsValid ? 0.5 : 1)}
            // opacity={updating || updated || !inputsValid ? 0.2 : 1}
            onPress={updateServer}  >
            <Heading size='$1' color={primaryTextColor}>Update Server</Heading>
          </Button>

          {/* <XStack f={1} /> */}
        </XStack>
        : undefined}
    >
      <AccountOrServerContextProvider value={accountOrServer}>
        <YStack f={1} jc="center" ai="center" space w='100%'>
          {server ?
            <YStack mb='$2' w='100%' jc="center" ai="center" >
              <ScrollView w='100%'>
                <YStack gap='$2' w='100%' maw={800} paddingHorizontal='$3' als='center' marginHorizontal='auto'>
                  {savedServer ? undefined : <YStack mt='$2'>
                    <Heading ta="center" fow="800">Server not configured. Add it through your Accounts screen, or autoconfigure it, first.</Heading>
                    <Paragraph ta="center" fow="800">{`Server URL: ${requestedServerUrl}`}</Paragraph>
                    {requestedServerUrlValid ? <Button theme='active' mt='$2' onPress={() => {
                      let [newServerProtocol, newServerHost] = requestedServerUrlParts;
                      let newServerSecure = newServerProtocol == 'https';
                      // dispatch(upsertServer({
                      //   host: newServerHost!,
                      //   secure: newServerSecure,
                      // }));
                      getServerClient({ host: newServerHost!, secure: newServerSecure }, { skipUpsert: false })
                    }}>
                      Autoconfigure Server <Heading size='$3'>{requestedServerUrl}</Heading>
                    </Button>
                      : <>
                        <Heading color={warningAnchorColor} size='$3' ta={'center'}>Server URL is invalid.</Heading>
                        <Heading color={warningAnchorColor} size='$3' ta={'center'}>Server URL format: [http|https]:valid_hostname</Heading>
                      </>}
                  </YStack>}
                  {/* {serverIsSelected ? undefined : <XStack>
                  <XStack my='auto'><AlertTriangle /></XStack>
                  <YStack my='auto' f={1}>
                    <Heading mt='$3' size='$3' als='center' ta='center'>Currently browsing on a different server</Heading>

                    <Heading whiteSpace="nowrap" maw={200} overflow='hidden' als='center' opacity={selectedServer?.serverConfiguration?.serverInfo?.name ? 1 : 0.5}>
                      {selectedServer?.serverConfiguration?.serverInfo?.name || 'Unnamed'}
                    </Heading>
                    <Heading size='$3' als='center' marginTop='$2'>
                      {selectedServer?.host}
                    </Heading>
                    <Button onPress={() => dispatch(selectServer(server))} mt='$3' theme='active' size='$3'>
                      Switch to&nbsp;<Heading size='$3'>{server.host}</Heading>
                    </Button>
                  </YStack>
                </XStack>} */}
                  {section === 'about' ? <>
                    <Heading size='$9' als='center' mt='$3'>About {specificServer ? 'Community' : 'Server'}</Heading>
                    <ServerCard server={{ ...server, serverConfiguration: updatedConfiguration }} disableHeightLimit />
                    <Button {...aboutRellmLink} size='$4' my='$2' {...themedButtonBackground(navColor, navTextColor)}
                      iconAfter={
                        <>
                          <Github color={navTextColor} />
                          <Container color={navTextColor} />
                          <Heart color={navTextColor} />
                        </>
                      }>
                      <XStack gap='$3' my='auto'>
                        <Info size='$3' color={navTextColor} />
                        <Heading size='$2' my='auto' color={navTextColor}>Powered by <Text fontSize='$6' color={navTextColor}>Rellm</Text></Heading>
                      </XStack>
                    </Button>
                    <Button mb='$2' onPress={() => setShowVersionInfo(!showVersionInfo)}>
                      <XStack mt='$1' w='100%'>
                        <Heading my='auto' size='$3' f={1}>Service Version</Heading>
                        <Paragraph my='auto'>{serviceVersion?.version}</Paragraph>

                        <XStack animation='standard' my='auto' ml='$2' rotate={showVersionInfo ? '90deg' : '0deg'}>
                          <ChevronRight />
                        </XStack>
                      </XStack>
                    </Button>
                    <AnimatePresence>
                      {showVersionInfo ? <XStack key='version-info' ml='auto' flexWrap='wrap' animation='standard' {...standardAnimation}>
                        <Button {...protocolDocsLink} target='_blank' size='$2' ml='auto' mb='$2' {...themedButtonBackground(navColor, navTextColor)}
                          iconAfter={<Binary size='$2' />}>
                          <Heading size='$1' color={navTextColor}>Protocol Docs</Heading>
                        </Button>
                        <Button {...flutterUiLink} target='_blank' size='$2' ml='$2' mb='$2' {...themedButtonBackground(navColor, navTextColor)}
                          iconAfter={<TabletSmartphone size='$1' />}>
                          <Heading size='$1' color={navTextColor}>Flutter UI</Heading>
                        </Button>

                        {githubVersion
                          ? <XStack ml='auto' mb='$2'>
                            <Button {...githubLink} target='_blank' size='$2' ml='$2'   {...themedButtonBackground(navColor, navTextColor)}
                              iconAfter={Github}>
                              <Heading size='$1' color={navTextColor}>View #{githubVersion} on GitHub</Heading>
                            </Button>
                          </XStack>
                          : undefined}

                      </XStack>
                        : undefined}
                    </AnimatePresence>
                    <Heading size='$3'>Name</Heading>
                    {isAdmin
                      ? <>
                        <Input value={name ?? ''} opacity={name && name != '' ? 1 : 0.5}
                          placeholder='The name of your community.' onChangeText={t => setName(t)} />
                        <Paragraph size='$1' ml='auto'>
                          Break lines with any emoji or &quot;|&quot;.
                        </Paragraph>
                        {/* <ScrollView horizontal> */}
                        <Heading size='$1' my='$2'>Name and Logo Previews</Heading>
                        <XStack mx='auto' gap='$3' my='$2'>
                          <XStack h={48} overflow='hidden'>
                            <ServerNameAndLogo server={{ ...server, serverConfiguration: updatedConfiguration }} />
                          </XStack>
                          <XStack h={72} w={72} o={0.5} my='auto'>
                            <ServerNameAndLogo server={{ ...server, serverConfiguration: updatedConfiguration }} shrinkToSquare />
                          </XStack>
                        </XStack>
                        {/* </ScrollView> */}
                        <XStack mx='auto' mb='$5'>
                          <ServerNameAndLogo server={{ ...server, serverConfiguration: updatedConfiguration }} enlargeSmallText />
                        </XStack>
                      </>
                      : <Heading opacity={name && name != '' ? 1 : 0.5}>{name || 'Unnamed'}</Heading>}

                    <Heading size='$3' mt='$2'>Description</Heading>
                    {isAdmin ?
                      <TextArea value={description ?? ''} opacity={description && description != '' ? 1 : 0.5}
                        onChangeText={t => setDescription(t)} h='$14'
                        placeholder='A description of the purpose of your community, any general guidelines, etc.' />
                      : description && description != ''
                        ? <TamaguiMarkdown text={description} />
                        : <Paragraph opacity={0.5}>No description set.</Paragraph>}

                    <Heading size='$3'>Privacy Policy</Heading>
                    {isAdmin ?
                      <TextArea value={privacyPolicy ?? ''} opacity={privacyPolicy && privacyPolicy != '' ? 1 : 0.5}
                        onChangeText={t => setPrivacyPolicy(t)} h='$14'
                        placeholder='A privacy policy stating how you plan to use user data.' />
                      : privacyPolicy && privacyPolicy != ''
                        ? <TamaguiMarkdown text={privacyPolicy} />
                        : <Paragraph opacity={0.5}>No privacy policy set.</Paragraph>}


                    <Heading size='$3'>Media Policy</Heading>
                    {isAdmin ?
                      <TextArea value={mediaPolicy ?? ''} opacity={mediaPolicy && mediaPolicy != '' ? 1 : 0.5}
                        onChangeText={t => setMediaPolicy(t)} h='$14'
                        placeholder='A media policy explaining clearly to users who owns rights to uploaded media.' />
                      : mediaPolicy && mediaPolicy != ''
                        ? <TamaguiMarkdown text={mediaPolicy} />
                        : <Paragraph opacity={0.5}>No media policy set.</Paragraph>}

                    {adminList.length > 0
                      ? <Heading size='$4'>Admins</Heading>
                      : undefined}
                    <AutoAnimatedList style={{ width: '100%', marginLeft: 5, marginRight: 5 }} >
                      <div key='pagest-top' id='pages-top' style={{ maxWidth: '100%' }}>
                        <PageChooser {...adminPagination} />
                      </div>
                      {paginatedAdmins?.map((user) => {
                        return <div style={{ width: '100%' }} key={`user-${federatedId(user)}`}>
                          <YStack w='100%' my='$2'>
                            <UserCard user={user} isPreview />
                          </YStack>
                        </div>;
                      })}

                      <div key='pages-bottom' id='pages-bottom' style={{ maxWidth: '100%' }}>
                        <PageChooser {...adminPagination} showResultCounts pageTopId='pages-top'
                          entityName={{ singular: 'admin', plural: 'admins' }}
                        />
                      </div>
                    </AutoAnimatedList>
                  </>
                    : undefined}
                  {/* <AnimatePresence> */}

                  {section === 'theme' ? <>
                    <Heading size='$9' als='center' mt='$3'>Server Theme</Heading>
                    {isAdmin || logo?.squareMediaId || logo?.wideMediaId
                      ? <>
                        <Heading size='$7' mt='$2'>Server Logo</Heading>

                        {isAdmin || logo?.wideMediaId
                          ? <Heading size='$2' mt='$2'>Square Logo/Favicon</Heading>
                          : undefined}
                        {logo?.squareMediaId
                          ? <XStack mb='$2'>
                            <MediaRenderer media={Media.create({ id: logo?.squareMediaId })} forceImage />
                          </XStack>
                          : undefined}
                        {isAdmin
                          ? <SingleMediaChooser mediaUseName='Square Logo/Icon'
                            selectedMedia={logo ? { id: logo.squareMediaId } as MediaRef : undefined}
                            setSelectedMedia={v => setLogo({ ...(logo ?? {}), squareMediaId: v?.id })} />
                          : undefined}

                        {isAdmin || logo?.wideMediaId
                          ? <Heading size='$2' mt='$2'>Wide Logo</Heading>
                          : undefined}
                        {logo?.wideMediaId ?
                          <XStack mb='$2'>
                            <MediaRenderer media={Media.create({ id: logo?.wideMediaId })} forceImage />
                          </XStack>
                          : undefined}
                        {isAdmin
                          ? <SingleMediaChooser mediaUseName='Wide Logo'
                            selectedMedia={logo ? { id: logo.wideMediaId } as MediaRef : undefined}
                            setSelectedMedia={v => setLogo({ ...(logo ?? {}), wideMediaId: v?.id })} />
                          : undefined}
                      </>
                      : undefined}
                    <Heading size='$7' mt='$2'>Colors</Heading>
                    {/* </AnimatePresence> */}
                    <XStack mt='$2'>
                      <Heading my='auto' size='$3' f={1}>Primary Color</Heading>
                      {isAdmin
                        ? <Input mr='$2' my='auto' w={100} value={primaryColorHex} color={primaryColorValid ? undefined : 'red'} onChange={(e) => setPrimaryColorHex(e.nativeEvent.text)} />
                        : <Paragraph mr='$2' my='auto'>{primaryColorHex}</Paragraph>}
                      <XStack my='auto' w={50} h={30} backgroundColor={primaryColorHex} />
                    </XStack>
                    {isAdmin ? <XStack als='center'>
                      <HexColorPicker color={primaryColorHex} onChange={setPrimaryColorHex} />
                    </XStack> : undefined}

                    <XStack mt='$2'>
                      <Heading my='auto' size='$3' f={1}>Navigation Color</Heading>
                      {isAdmin
                        ? <Input mr='$2' my='auto' w={100} value={navColorHex} color={navColorValid ? undefined : 'red'} onChange={(e) => setNavColorHex(e.nativeEvent.text)} />
                        : <Paragraph mr='$2' my='auto' >{navColorHex}</Paragraph>}
                      <XStack my='auto' w={50} h={30} backgroundColor={navColorHex} />
                    </XStack>
                    {isAdmin ? <XStack als='center'>
                      <HexColorPicker color={navColorHex} onChange={setNavColorHex} />
                    </XStack> : undefined}
                    <XStack mt='$3' />
                  </>
                    : undefined}

                  {section === 'settings' ? <>
                    <Heading size='$9' als='center' mt='$3'>Server Settings</Heading>
                    <YStack gap='$3' mt='$3'>
                      <YStack gap='$2' als='center'>
                        <Heading size='$4'>Default Web UI</Heading>
                        <WebUserInterfacePicker
                          webUserInterface={webUserInterface}
                          onChange={setWebUserInterface}
                          disabled={!isAdmin} />
                      </YStack>

                      {<PermissionsEditor label='Anonymous User Permissions'
                        description='These permissions are granted to users who are not logged in.'
                        {...anonymousPermissionsEditorProps} />}

                      {<PermissionsEditor label='Default User Permissions'
                        description='These permissions are granted to new users by default. (They may later be revoked.)'
                        {...defaultPermissionsEditorProps} />}

                      {<PermissionsEditor label='Basic User Permissions'
                        description='Users with the "Grant Basic Permissions" permission can grant these permissions to other users.'
                        {...basicPermissionsEditorProps} />}
                    </YStack>

                  </>
                    : undefined}

                  {section === 'federation' ? <>
                    <Heading size='$9' als='center' mt='$3'>Federation</Heading>
                    <Heading size='$4' mt='$3'>Federated Servers</Heading>
                    <Paragraph size='$1' mb='$3'>
                      Rellm servers can federate with each other (via a particular pattern I'm dubbing "delightful federation" that means "no server-to-server needed").
                      This surfaces to users as "recommended servers," "servers" (or "added servers"), and "pinned servers" in the navigation (for pinned servers) and the account section of their UI.
                      Rellm as a protocol is designed so that servers don't really need to talk to each other much; the federation sits mostly on the client-side
                      and is backed by DNS{window.location.toString().startsWith('https') ? ', TLS, ' : ' '}
                      and CORS. (Strict CORS is not yet implemented for Rellm's Tonic/gRPC or Rocket/HTTP servers; this would be{' '}
                      <Anchor ai='center' size='$1' href='https://github.com/JonLatane/rellm/issues/2' color={navAnchorColor}>
                        a good first issue for new GitHub/FOSS contributors
                      </Anchor>.)
                    </Paragraph>
                    {(federatedServers?.length ?? 0) === 0 ? <Paragraph size='$1' ml='auto' mr='auto' p='$5'>
                      No federated servers.
                    </Paragraph> : undefined}
                    <AutoAnimatedList>
                      {federatedServers?.map((server, index) =>

                        <div key={`server-${server.host}`}>
                          <XStack ml='$3' mb='$2' w='100%' gap='$2' ai='center'>
                            <Text my='auto' fontFamily='$body' fontSize='$3' mr='$2'>{`${index + 1}.`}</Text>
                            <Card elevate bordered f={1} px='$3'>
                              <YStack key={`recommendedServer-${server.host}`} w='100%' my='$2' alignContent='center' ai='center'>

                                <XStack mb='$2' w='100%' gap='$2' ai='center'>
                                  <Heading f={1} fontFamily='$body' size='$1' >{server.host}</Heading>
                                  {isAdmin
                                    ? <>
                                      <Button mr='$1' icon={ChevronUp} size='$2'
                                        disabled={index === 0}
                                        o={index === 0 ? 0.5 : 1}
                                        onPress={() => {
                                          const data = [...federatedServers];
                                          if (index > 0) {
                                            const element = data.splice(index, 1)[0]!;
                                            data.splice(index - 1, 0, element);
                                          }
                                          setFederatedServers(data);
                                        }} />
                                      <Button mr='$1' icon={ChevronDown} size='$2'
                                        disabled={index === federatedServers.length - 1}
                                        o={index === federatedServers.length - 1 ? 0.5 : 1}
                                        onPress={() => {
                                          const data = [...federatedServers];
                                          // const index = data.indexOf(host);
                                          if (index < federatedServers.length - 1) {
                                            const element = data.splice(index, 1)[0]!;
                                            data.splice(index + 1, 0, element);
                                          }
                                          setFederatedServers(data);
                                        }} />
                                      <Button icon={Delete} size='$2' onPress={() => setFederatedServers(federatedServers?.filter(s => s.host !== server.host))} />
                                    </>
                                    : undefined}
                                </XStack>
                                <RecommendedServer host={server.host} />
                                <YStack ai="center" gap="$1" opacity={isAdmin ? 1 : 0.5}>
                                  <XStack ai="center" gap="$4">
                                    <Label pr="$0" miw={90} jc="flex-end" size='$2'
                                      o={!server.configuredByDefault ? 1 : 0.5}
                                      htmlFor={`${server.host}-add-by-default`}>
                                      Recommend Only
                                    </Label>
                                    <Switch id={`${server.host}-add-by-default`} size='$2' defaultChecked={server.configuredByDefault}
                                      checked={server.configuredByDefault} value={server.configuredByDefault?.toString()}
                                      disabled={!isAdmin}
                                      onCheckedChange={(checked) => setFederatedServers(federatedServers.map((s, i) => i === index ? { ...s, configuredByDefault: checked, pinnedByDefault: checked && s.pinnedByDefault } : s))}>
                                      <Switch.Thumb animation='standard' backgroundColor='$background' />
                                    </Switch>
                                    <Label pr="$0" miw={90} jc="flex-end" size='$2'
                                      o={server.configuredByDefault ? 1 : 0.5}
                                      htmlFor={`${server.host}-add-by-default`}>
                                      Add By Default
                                    </Label>
                                  </XStack>
                                  {/* <SeparatorHorizontal /> */}
                                  <XStack ai="center" gap="$4">
                                    <Switch id={`${server.host}-pin-by-default`} size='$2' defaultChecked={server.pinnedByDefault}
                                      checked={server.pinnedByDefault} value={server.pinnedByDefault?.toString()}
                                      disabled={!isAdmin}
                                      onCheckedChange={(checked) => setFederatedServers(federatedServers.map((s, i) => i === index ? { ...s, pinnedByDefault: checked, configuredByDefault: checked || s.configuredByDefault } : s))}>
                                      <Switch.Thumb animation='standard' backgroundColor='$background' />
                                    </Switch>
                                    <Label pr="$0" miw={90} jc="flex-end" size='$2' o={server.pinnedByDefault ? 1 : 0.5}
                                      htmlFor={`${server.host}-pin-by-default`}>
                                      Pin By Default
                                    </Label>
                                  </XStack>
                                </YStack>
                              </YStack>
                            </Card>
                          </XStack>
                        </div>
                      )}
                    </AutoAnimatedList>
                    {isAdmin
                      ? <>
                        <Input value={newRecommendedHostName ?? ''} opacity={newRecommendedHostName && newRecommendedHostName != '' ? 1 : 0.5}
                          placeholder='Recommend a Rellm host' onChangeText={t => setNewRecommendedHostName(t)} />
                        <Button mt='$2' mb='$5'
                          disabled={!isNewRecommendedHostNameValid}
                          o={isNewRecommendedHostNameValid ? 1 : 0.5}
                          onPress={recommendServer}
                        >
                          Recommend Server
                        </Button>
                      </>
                      : undefined}
                  </>
                    : undefined}

                  {section === 'cdn' ? <>
                    <Heading size='$9' als='center' mt='$3'>External CDN Settings</Heading>
                    <Heading size='$1' als='center' mt='$3'>
                      (Mostly for use with <Anchor size='$1' {...cloudflareLink}>Cloudflare</Anchor>.)
                    </Heading>
                    {/* {isAdmin ? <> */}
                    <Paragraph size='$1'>
                      To improve performance, administrators can put their Rellm server's HTML
                      and Media behind Cloudflare, using a separate host as the gRPC backend.
                    </Paragraph>
                    <Paragraph size='$1'>
                      For instance, to use Cloudflare to point jonline.io to a backend
                      at jonline.io.itsj.online, you would:
                    </Paragraph>
                    {[
                      'Setup and secure your instance on jonline.io.itsj.online, whose DNS is probably managed by your Kubernetes provider (I use DigitalOcean), so you can secure it with Cert-Manager.',
                      'For extra security: apply a firewall with your Kubernetes provider on the jonline.io.itsj.online host that allows all traffic on port 27707, and only traffic from Cloudflare IPs otherwise.',
                      'Turn on External CDN Support, set the Backend Domain below to jonline.io.itsj.online, Frontend Domain to jonline.io, and press Update Server.',
                      'Restart your deployment in Kubernetes. (Maybe we can remove this step one day!)',
                      'For jonline.io, whose DNS is managed by Cloudflare, create a CNAME record in Cloudflare for jonline.io pointing to notj.online. Turn on Cloudflare\'s HTTPS "proxy" feature, and add a Page Rule for "Cache Level: Cache Everything" for jonline.io/*.'
                    ].map((text, index) => <XStack ml='$3' mb='$2'>
                      <Text fontFamily='$body' fontSize='$1' mr='$2'>{`${index + 1}.`}</Text>
                      <Text fontFamily='$body' fontSize='$1' >{text}</Text>
                    </XStack>)}
                    {/* </> : undefined} */}
                    <XStack mt='$3' mb='$2'>
                      <YStack f={1}>
                        <Heading size='$3' my='auto'>External CDN HTTP Support</Heading>
                        <Paragraph size='$1'>Service restart required after setting.</Paragraph>
                      </YStack>
                      <Switch size="$5" margin='auto'
                        defaultChecked={externalCdnConfig != undefined}
                        checked={externalCdnConfig != undefined}
                        value={(externalCdnConfig != undefined).toString()}
                        disabled={!isAdmin}
                        opacity={isAdmin ? 1 : 0.5}
                        onCheckedChange={(checked) => setExternalCdnConfig(
                          checked ? ExternalCDNConfig.fromPartial({ backendHost: '', frontendHost: '' }) : undefined
                        )}>
                        <Switch.Thumb animation='standard' backgroundColor='$background' />
                      </Switch>
                    </XStack>
                    {isAdmin || externalCdnConfig
                      ? <YStack>
                        <Heading size='$2' f={1}
                          opacity={externalCdnConfig ? 1 : 0.5}>Frontend Host</Heading>
                        <Paragraph size='$1'></Paragraph>
                        {isAdmin
                          ? <Input editable={externalCdnConfig != undefined}
                            opacity={externalCdnConfig && externalCdnConfig.frontendHost.length > 0 ? 1 : 0.5}
                            value={externalCdnConfig?.frontendHost ?? ''}
                            placeholder='e.g.: jonline.io'
                            onChangeText={t => externalCdnConfig && setExternalCdnConfig({ ...(externalCdnConfig!), frontendHost: t })} />
                          : <Paragraph opacity={externalCdnConfig && externalCdnConfig.frontendHost.length > 0 ? 1 : 0.5}>
                            {externalCdnConfig?.frontendHost || ''}
                          </Paragraph>}
                        <Heading mt='$2' size='$2' f={1}
                          opacity={externalCdnConfig ? 1 : 0.5}>Backend Host</Heading>
                        <Paragraph size='$1'></Paragraph>
                        {isAdmin
                          ? <Input editable={externalCdnConfig != undefined}
                            opacity={externalCdnConfig && externalCdnConfig.backendHost.length > 0 ? 1 : 0.5}
                            value={externalCdnConfig?.backendHost ?? ''}
                            placeholder='e.g.: jonline.io.itsj.online'
                            onChangeText={t => externalCdnConfig && setExternalCdnConfig({ ...(externalCdnConfig!), backendHost: t })} />
                          : <Paragraph opacity={externalCdnConfig && externalCdnConfig.backendHost.length > 0 ? 1 : 0.5}>
                            {externalCdnConfig?.backendHost || ''}
                          </Paragraph>}
                      </YStack>
                      : undefined}
                    <XStack mt='$3'>
                      <YStack f={1}>
                        <Heading size='$3' my='auto'
                          opacity={isAdmin && externalCdnConfig ? 1 : 0.5}>External CDN gRPC Support</Heading>
                        <Paragraph size='$1'
                          opacity={isAdmin && externalCdnConfig ? 1 : 0.5}>Additional service restart required. Ensure CDN HTTP support is working before enabling CDN gRPC support. <Text fontStyle='italic' fontWeight='900'>In case enabling makes this UI inaccessible, make sure you can shell in</Text> (<Text fontFamily='$mono'>make backend_shell</Text>, using Rellm Makefiles) and run <Text fontFamily='$mono'>./opt/disable_cdn_grpc</Text> to revert this setting.</Paragraph>
                      </YStack>
                      <Switch size="$5" margin='auto'
                        defaultChecked={externalCdnConfig?.cdnGrpc}
                        checked={externalCdnConfig?.cdnGrpc}
                        value={(!!externalCdnConfig?.cdnGrpc).toString()}
                        disabled={!isAdmin || !externalCdnConfig}
                        opacity={isAdmin && externalCdnConfig ? 1 : 0.5}
                        onCheckedChange={(checked) => setExternalCdnConfig(
                          externalCdnConfig
                            ? { ...externalCdnConfig, cdnGrpc: checked }
                            : undefined
                        )}>
                        <Switch.Thumb animation='standard' backgroundColor='$background' />
                      </Switch>
                    </XStack>
                  </>
                    : undefined}

                  {isWeb && isAdmin ? <YStack h={50} /> : undefined}
                </YStack>
              </ScrollView>

            </YStack>
            : <YStack>
              <Heading ta="center" fow="800">Server not configured. Add it through your Accounts screen, or autoconfigure it, first.</Heading>
              <Paragraph ta="center" fow="800">{`Server URL: ${requestedServerUrl}`}</Paragraph>
              {requestedServerUrlValid ? <Button theme='active' mt='$2' onPress={() => {
                let [newServerProtocol, newServerHost] = requestedServerUrlParts;
                let newServerSecure = newServerProtocol == 'https';
                // dispatch(upsertServer({
                //   host: newServerHost!,
                //   secure: newServerSecure,
                // }));
                getServerClient({ host: newServerHost!, secure: newServerSecure }, { skipUpsert: false })
              }}>
                Autoconfigure Server <Heading size='$3'>{requestedServerUrl}</Heading>
              </Button>
                : <>
                  <Heading color={warningAnchorColor} size='$3' ta={'center'}>Server URL is invalid.</Heading>
                  <Heading color={warningAnchorColor} size='$3' ta={'center'}>Server URL format: [http|https]:valid_hostname</Heading>
                </>}
            </YStack>
          }
        </YStack>
      </AccountOrServerContextProvider>
    </TabsNavigation>
  )
}
