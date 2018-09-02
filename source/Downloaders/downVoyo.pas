(******************************************************************************

______________________________________________________________________________

YTD v1.00                                                    (c) 2009-12 Pepak
http://www.pepak.net/ytd                                  http://www.pepak.net
______________________________________________________________________________


Copyright (c) 2009-12 Pepak (http://www.pepak.net)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Pepak nor the
      names of his contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PEPAK BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

******************************************************************************)

unit downVoyo;
{$INCLUDE 'ytd.inc'}

{
  Podweby Novy maji konfiguraci ulozenou v zasifrovanem konfiguracnim souboru,
  napr. "http://tn.nova.cz/bin/player/flowplayer/config.php?site=23000&realSite=77000&subsite=574&section=77300&media=752873&jsVar=flowConf1&mute=0&size=&pWidth=600&pHeight=383"
  Jeho desifrovani je v metode IdentifyDownloader, heslo se ziska dekompilaci
  13-flowplayer.swf a hledanim "AES". Toto se tyka napr. poker.nova.cz,
  poklicka.nova.cz a dalsich.

  Udaje pro ziskani playlistu pro RTMP verzi se daji ziskat dekompilovanim
  http://voyo.nova.cz/static/shared/app/flowplayer/13-flowplayer.nacevi-3.1.5-06-002.swf
  ve skriptu org.flowplayer.nacevi.Nacevi (sestaveni URL a ziskani a zpracovani
  playlistu - zejmena jde o metody getHashString a onGetTimeStamp). Potreba je
  pro to ResolverSecret, ktery se da najit v desifrovanem konfiguracnim souboru
  jako polozka "secret" (primo v SWF je jen falesna hodnota pro zmatelni nepritele).

  Vhodne testovaci porady:
    Nova:
    - MS:   http://voyo.nova.cz/product/26894-testovaci-video-okresni-prebor-16
    - RTMP: http://voyo.nova.cz/product/porady/32684-automag-40-3-12-2012
    Markiza:
            http://voyo.markiza.sk/produkt/filmy/167-testovacie-video-voyo
}

{.$DEFINE VOYO_PLUS}
  // Zatim nefunguje

interface

uses
  SysUtils, Classes, {$IFDEF DELPHI2009_UP} Windows, {$ENDIF}
  uPCRE, uXml, uCrypto, HttpSend, SynaCode,
  uOptions, uCompatibility, uFunctions,
  {$IFDEF GUI}
    guiDownloaderOptions,
    {$IFDEF GUI_WINAPI}
      guiOptionsWINAPI_Nova,
    {$ELSE}
      guiOptionsVCL_Nova,
    {$ENDIF}
  {$ENDIF}
  uDownloader, uCommonDownloader, uNestedDownloader,
  uRtmpDirectDownloader, uMSDirectDownloader, uHttpDirectDownloader;

type
  TDownloader_Voyo = class(TNestedDownloader)
    private
    protected
      LowQuality: boolean;
      ResolverSecret: string;
      ConfigPassword: string;
      MediaDataRegExp: TRegExp;
      MovieIDRegExp: TRegExp;
      PlayerParamsRegExp: TRegExp;
      PlayerParamsItemRegExp: TRegExp;
      RegExpFlowPlayerConfigUrl: TRegExp;
      RegExpFlowPlayerConfig: TRegExp;
      JSONConfigRegExp: TRegExp;
      ResolverSecretRegExp: TRegExp;
    protected
      function GetMovieInfoUrl: string; override;
      procedure SetOptions(const Value: TYTDOptions); override;
      function IdentifyDownloader(var Page: string; PageXml: TXmlDoc; Http: THttpSend; out Downloader: TDownloader): boolean; override;
      function TryHTTPDownloader(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig: string; out Downloader: TDownloader): boolean;
      function TryMSDownloader(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig: string; out Downloader: TDownloader): boolean;
      function TryRTMPDownloader(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig: string; out Downloader: TDownloader): boolean;
      function GetFlowPlayerConfigRegExp: string; virtual; abstract;
      function GetDecryptedConfig(Http: THttpSend; const Url: string; out Config: string): boolean;
      function GetResolverSecret(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID: string; out ResolverSecret: string): boolean;
    public
      class function Features: TDownloaderFeatures; override;
      {$IFDEF GUI}
      class function GuiOptionsClass: TFrameDownloaderOptionsPageClass; override;
      {$ENDIF}
      constructor Create(const AMovieID: string); override;
      destructor Destroy; override;
    end;

const
  OPTION_VOYO_LOWQUALITY {$IFDEF MINIMIZESIZE} : string {$ENDIF} = 'low_quality';
  OPTION_VOYO_LOWQUALITY_DEFAULT = False;
  OPTION_VOYO_SECRET {$IFDEF MINIMIZESIZE} : string {$ENDIF} = 'secret';
  OPTION_VOYO_SECRET_DEFAULT = '';
  OPTION_VOYO_CONFIG_PASSWORD {$IFDEF MINIMIZESIZE} : string {$ENDIF} = 'config_password';
  OPTION_VOYO_CONFIG_PASSWORD_DEFAULT = '';

implementation

uses
  uStringConsts,
  uDownloadClassifier,
  uMessages;

const
  REGEXP_MOVIE_TITLE = REGEXP_TITLE_META_OGTITLE;
  REGEXP_MEDIADATA = '\bmainVideo\s*=\s*new\s+mediaData\s*\(\s*(?P<PROD_ID>\d+)\s*,\s*(?P<UNIT_ID>\d+)\s*,\s*(?P<MEDIA_ID>\d+)'; // dalsi tri parametry jsou: Archivovane, Extra, Zive
  REGEXP_STREAMID = '<param\s+value=\\"(?:[^,]*,)*identifier=(?P<ID>(?P<YEAR>\d{4})-(?P<MONTH>\d{2})-[^",]+)';
  REGEXP_PLAYERPARAMS = 'voyoPlayer\.params\s*=\s*\{(?P<PARAMS>.*?)\}\s*;';
  REGEXP_PLAYERPARAMS_ITEM = '\b(?P<VARNAME>[a-z0-9_]+)\s*:\s*(?P<QUOTE>["'']?)(?P<VARVALUE>.*?)(?P=QUOTE)\s*(?:,|$)';
  REGEXP_CONFIG_URL = '<script\b[^>]*?\ssrc="(?P<URL>https?://[^"]+?/config\.php\?.+?)"';
  REGEXP_JSON_CONFIG = '"(?P<VARNAME>[^"]+)"\s*:\s*(?P<VARVALUE>(?:"[^"]*"|\w+))';
  REGEXP_RESOLVER_SECRET = '"secret"\s*:\s*"(?P<SECRET>.*?)"';

resourcestring
  ERR_MISSING_CONFIG_PASSWORD = 'Invalid configuration: Config password not set.';

type
  TDownloader_Voyo_MS = class(TMSDirectDownloader);

  TDownloader_Voyo_RTMP = class(TRTMPDirectDownloader)
    public
      class function Features: TDownloaderFeatures; override;
    end;

{ TDownloader_Voyo }

class function TDownloader_Voyo.Features: TDownloaderFeatures;
begin
  Result := inherited Features + TDownloader_Voyo_RTMP.Features + TDownloader_Voyo_MS.Features;
end;

{$IFDEF GUI}
class function TDownloader_Voyo.GuiOptionsClass: TFrameDownloaderOptionsPageClass;
begin
  Result := TFrameDownloaderOptionsPage_Nova;
end;
{$ENDIF}

constructor TDownloader_Voyo.Create(const AMovieID: string);
begin
  inherited;
  InfoPageEncoding := peUTF8;
  MovieTitleRegExp := RegExCreate(REGEXP_MOVIE_TITLE);
  MediaDataRegExp := RegExCreate(REGEXP_MEDIADATA);
  MovieIDRegExp := RegExCreate(REGEXP_STREAMID);
  PlayerParamsRegExp := RegExCreate(REGEXP_PLAYERPARAMS);
  PlayerParamsItemRegExp := RegExCreate(REGEXP_PLAYERPARAMS_ITEM);
  RegExpFlowPlayerConfigUrl := RegExCreate(REGEXP_CONFIG_URL);
  RegExpFlowPlayerConfig := RegExCreate(GetFlowPlayerConfigRegExp);
  JSONConfigRegExp := RegExCreate(REGEXP_JSON_CONFIG);
  ResolverSecretRegExp := RegExCreate(REGEXP_RESOLVER_SECRET);
  LowQuality := OPTION_VOYO_LOWQUALITY_DEFAULT;
  ResolverSecret := OPTION_VOYO_SECRET_DEFAULT;
  ConfigPassword := OPTION_VOYO_CONFIG_PASSWORD_DEFAULT;
end;

destructor TDownloader_Voyo.Destroy;
begin
  RegExFreeAndNil(MovieTitleRegExp);
  RegExFreeAndNil(MediaDataRegExp);
  RegExFreeAndNil(MovieIDRegExp);
  RegExFreeAndNil(PlayerParamsRegExp);
  RegExFreeAndNil(PlayerParamsItemRegExp);
  RegExFreeAndNil(RegExpFlowPlayerConfigUrl);
  RegExFreeAndNil(RegExpFlowPlayerConfig);
  RegExFreeAndNil(JSONConfigRegExp);
  RegExFreeAndNil(ResolverSecretRegExp);
  inherited;
end;

function TDownloader_Voyo.GetMovieInfoUrl: string;
begin
  Result := MovieID;
end;

procedure TDownloader_Voyo.SetOptions(const Value: TYTDOptions);
begin
  inherited;
  LowQuality := Value.ReadProviderOptionDef(Provider, OPTION_VOYO_LOWQUALITY, OPTION_VOYO_LOWQUALITY_DEFAULT);
  ResolverSecret := Value.ReadProviderOptionDef(Provider, OPTION_VOYO_SECRET, OPTION_VOYO_SECRET_DEFAULT);
  ConfigPassword := Value.ReadProviderOptionDef(Provider, OPTION_VOYO_CONFIG_PASSWORD, OPTION_VOYO_CONFIG_PASSWORD_DEFAULT);
end;

function TDownloader_Voyo.IdentifyDownloader(var Page: string; PageXml: TXmlDoc; Http: THttpSend; out Downloader: TDownloader): boolean;
var
  Params, SiteID, SectionID, Subsite, ProductID, UnitID, MediaID: string;
  ConfigUrl, DecryptedConfig: string;
  HaveParams: boolean;
  {$IFDEF DEBUG}
  Secret: string;
  {$ENDIF}
begin
  inherited IdentifyDownloader(Page, PageXml, Http, Downloader);
  Result := False;
  // Konfigurace prehravace muze mit nekolik zdroju
  HaveParams := False;
  SiteID := '';
  SectionID := '';
  Subsite := '';
  ProductID := '';
  UnitID := '';
  MediaID := '';
  // a) Mohou byt zasifrovane v javascriptove konfiguraci
  if not HaveParams then
    if GetRegExpVar(RegExpFlowPlayerConfigUrl, Page, 'URL', ConfigUrl) then
      if ConfigPassword = '' then
        begin
        SetLastErrorMsg(ERR_MISSING_CONFIG_PASSWORD);
        Exit;
        end
      else
        if GetDecryptedConfig(Http, ConfigUrl, DecryptedConfig) then
          if GetRegExpVarPairs(JSONConfigRegExp, DecryptedConfig, ['mediaID', 'sectionID', 'siteID'], [@MediaID, @SectionID, @SiteID]) then
            HaveParams := True;
  // b)Mohou byt primo ve zdrojove strance
  if not HaveParams then
    if GetRegExpVar(PlayerParamsRegExp, Page, 'PARAMS', Params) then
      if GetRegExpVarPairs(PlayerParamsItemRegExp, Params, ['siteId', 'sectionId', 'subsite'], [@SiteID, @SectionID, @Subsite]) then
        if GetRegExpVars(MediaDataRegExp, Page, ['PROD_ID', 'UNIT_ID', 'MEDIA_ID'], [@ProductID, @UnitID, @MediaID]) then
          HaveParams := True;
  // ResolverSecret lze ziskat strojove, pokud zname ConfigPassword
  {$IFDEF DEBUG}
  if HaveParams then
    if GetResolverSecret(Http, SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, Secret) then
      Writeln(Secret);
  {$ENDIF}
  // Aspon nektere z tech parametru jsou povinne
  if not HaveParams then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_INFO)
  else if (SiteID = '') or (SectionID = '') or (MediaID = '') then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_INFO)
  // Ted postupne vyzkousim jednotlive downloadery
  else if TryHTTPDownloader(Http, SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig, Downloader) then
    Result := True
  else if TryMSDownloader(Http, SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig, Downloader) then
    Result := True
  else if TryRTMPDownloader(Http, SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig, Downloader) then
    Result := True
  else
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_INFO);
end;

function TDownloader_Voyo.TryMSDownloader(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig: string; out Downloader: TDownloader): boolean;
const
  QualitySuffix: array[boolean] of string = ('-LQ', '-HQ');
  SoapQuality: array[0..2] of string = ('hd', 'hq', 'lq');
  SOAP_REQUEST = ''
    + '<GetSecuredUrl xmlns:i="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://streaming.kitd.cz/cdn/nova">'
    + '<token></token>'
    + '<mediaId>%0:s</mediaId>'
    + '<id>%1:s</id>'
    + '<type>Archive</type>'
    + '<format>%2:s</format>'
    + '</GetSecuredUrl>'
    ;
  NACEVI_BASE_URL = 'http://cdn1003.nacevi.cz/nova-vod-wmv/nova-vod-wmv/%s/%s/%s%s.wmv';
var
  InfoUrl, StreamInfo, Year, Month, ID, Url: string;
  MSDownloader: TMSDirectDownloader;
  RequestXml, ResponseXml: TXmlDoc;
  ResponseHeaderNode, ResponseBodyNode: TXmlNode;
  i: integer;
begin
  Result := False;
  if not Result then
    begin
    InfoUrl := Format('http://voyo.nova.cz/bin/eshop/ws/plusPlayer.php?x=playerFlash'
                      + '&prod=%0:s&unit=%1:s&media=%2:s&site=%3:s&section=%4:s&subsite=%5:s'
                      + '&embed=0&mute=0&size=&realSite=%3:s&width=704&height=441&hdEnabled=%6:d'
                      {$IFDEF VOYO_PLUS}
                      + '&hash=%7:s&dev=&8:s&wv=1&sts=%9:s&r=%10:d
                      {$ENDIF}
                      + '&finish=finishedPlayer', [
                      {0}ProductID, {1}UnitID, {2}MediaID, {3}SiteID, {4}SectionID, {5}Subsite
                      , {6}Integer(LowQuality)
                      {$IFDEF VOYO_PLUS}
                      , {7}Hash, {8}Device, {9}Timestamp, {10}Random(65535)
                      {$ENDIF}
                      ]);
    if DownloadPage(Http, InfoUrl, StreamInfo) then
      if GetRegExpVars(MovieIDRegExp, StreamInfo, ['YEAR', 'MONTH', 'ID'], [@Year, @Month, @ID]) then
        begin
        MovieUrl := Format(NACEVI_BASE_URL, [Year, Month, ID, QualitySuffix[not LowQuality]]);
        if not DownloadPage(Http, Url, hmHEAD) then
          MovieUrl := Format(NACEVI_BASE_URL, [Year, Month, ID, QualitySuffix[LowQuality]]);
        MSDownloader := TMSDirectDownloader.CreateWithName(MovieUrl, UnpreparedName);
        MSDownloader.Options := Options;
        Downloader := MSDownloader;
        Result := True;
        end;
    end;
  if not Result then
    begin
    if LowQuality then
      i := Pred(Length(SoapQuality))
    else
      i := 0;
    while (not Result) and (i >= 0) and (i < Length(SoapQuality)) do
      begin
      RequestXml := TXmlDoc.Create;
      try
        RequestXml.LoadFromBinaryString( {$IFDEF UNICODE} AnsiString {$ENDIF} (Format(SOAP_REQUEST, [MediaID, UnitID, SoapQuality[i]])));
        if DownloadSoap(Http, 'http://fcdn-dir.kitd.cz/Services/Player.asmx', 'http://streaming.kitd.cz/cdn/nova/GetSecuredUrl', nil, RequestXml.Root, ResponseXml, ResponseHeaderNode, ResponseBodyNode) then
          try
            if ResponseBodyNode <> nil then
              if GetXmlVar(ResponseBodyNode, 'GetSecuredUrlResponse/GetSecuredUrlResult', Url) then
                if ExtractUrlFileName(Url) <> 'nova-invalid' then
                  if Url <> '' then
                    if AnsiCompareText(Copy(Url, 1, 4), 'rtmp') <> 0 then
                      begin
                      MovieUrl := Url;
                      MSDownloader := TMSDirectDownloader.CreateWithName(MovieUrl, UnpreparedName);
                      MSDownloader.Options := Options;
                      Downloader := MSDownloader;
                      Result := True;
                      end;
          finally
            FreeAndNil(ResponseXml);
            end;
        if LowQuality then
          Dec(i)
        else
          Inc(i);
      finally
        FreeAndNil(RequestXml);
        end;
      end;
    end;
end;

function TDownloader_Voyo.TryRTMPDownloader(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig: string; out Downloader: TDownloader): boolean;
const
  NOVA_SERVICE_URL = 'http://master-ng.nacevi.cz/cdn.server/PlayerLink.ashx';
  NOVA_TIMESTAMP_URL = 'http://tn.nova.cz/lbin/time.php';
  NOVA_APP_ID = 'nova-vod';
var
  InfoXml: TXmlDoc;
  Node: TXmlNode;
  Timestamp, AppID, Signature, InfoUrl, Status, Url, BaseUrl, Quality: string;
  SignatureBytes: AnsiString;
  i: integer;
  RtmpDownloader: TDownloader_Voyo_RTMP;
begin
  Result := False;
  if DownloadPage(Http, NOVA_TIMESTAMP_URL, Timestamp) then
    begin
    Timestamp := Copy(Timestamp, 1, 14);
    AppID := UrlEncode(NOVA_APP_ID + '|' + MediaID);
    SignatureBytes := {$IFDEF UNICODE} AnsiString {$ENDIF} (NOVA_APP_ID + '|' + MediaID + '|' + Timestamp + '|' + ResolverSecret);
    SignatureBytes := MD5(SignatureBytes);
    SignatureBytes := EncodeBase64(SignatureBytes);
    Signature := UrlEncode( {$IFDEF UNICODE} string {$ENDIF} (SignatureBytes));
    InfoUrl := Format(NOVA_SERVICE_URL + '?c=%s&h=0&t=%s&s=%s&tm=nova&d=1', [AppID, Timestamp, Signature]);
    if DownloadXml(Http, InfoUrl, InfoXml) then
      try
        if GetXmlVar(InfoXml, 'status', Status) then
          if Status = 'Ok' then
            if GetXmlVar(InfoXml, 'baseUrl', BaseUrl) then
              if XmlNodeByPath(InfoXml, 'mediaList', Node) then
                for i := 0 to Pred(Node.NodeCount) do
                  if Node[i].Name = 'media' then
                    if GetXmlVar(Node[i], 'url', Url) then
                      if GetXmlVar(Node[i], 'quality', Quality) then
                        if (LowQuality and (Quality = 'lq')) or ((not LowQuality) and (Quality = 'hq')) then
                          begin
                          MovieUrl := Url;
                          RtmpDownloader := TDownloader_Voyo_RTMP.Create(Url);
                          RtmpDownloader.Options := Options;
                          RtmpDownloader.RtmpUrl := BaseUrl;
                          RtmpDownloader.Playpath := Url;
                          RtmpDownloader.SaveRtmpDumpOptions;
                          Downloader := RtmpDownloader;
                          Result := True;
                          Break;
                          end;
      finally
        FreeAndNil(InfoXml);
        end;
    end;
end;

function TDownloader_Voyo.GetResolverSecret(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID: string; out ResolverSecret: string): boolean;
var
  Url, ConfigPage, Secret: string;
begin
  Result := False;
  Url := Format('http://voyo.nova.cz/bin/eshop/ws/plusPlayer.php?x=playerFlash&prod=%s&unit=%s&media=%s&site=%s&section=%s&subsite=%s&embed=0&mute=0&size=&realSite=%s&width=704&height=441&hdEnabled=0&hash=&finish=finishedPlayer&dev=undefined&wv=0&sts=undefined&r=0.%d', [ProductID, UnitID, MediaID, SiteID, SectionID, Subsite, SiteID, UnixTimestamp]);
  if GetDecryptedConfig(Http, Url, ConfigPage) then
    if GetRegExpVar(ResolverSecretRegExp, ConfigPage, 'SECRET', Secret) then
      begin
      ResolverSecret := JSDecode(Secret);
      Result := True;
      end;
end;

function TDownloader_Voyo.GetDecryptedConfig(Http: THttpSend; const Url: string; out Config: string): boolean;
const
  AES_KEY_BITS = 128;
var
  ConfigPage, ConfigInfo, DecryptedConfig: string;
begin
  Result := False;
  if ConfigPassword <> '' then
    if DownloadPage(Http, Url, ConfigPage, peNone) then
      begin
      if GetRegExpVar(RegExpFlowPlayerConfig, ConfigPage, 'CONFIG', ConfigInfo) then
        begin
        ConfigInfo := JSDecode(ConfigInfo);
        //ConfigInfo := JSDecode(ConfigInfo);
        DecryptedConfig :=  {$IFDEF UNICODE} string {$ENDIF} (AESCTR_Decrypt(DecodeBase64( {$IFDEF UNICODE} AnsiString {$ENDIF} (ConfigInfo)),  {$IFDEF UNICODE} AnsiString {$ENDIF} (ConfigPassword), AES_KEY_BITS));
        if DecryptedConfig <> '' then
          begin
          Config := DecryptedConfig;
          Result := True;
          end;
        end;
      end;
end;

function TDownloader_Voyo.TryHTTPDownloader(Http: THttpSend; const SiteID, SectionID, Subsite, ProductID, UnitID, MediaID, DecryptedConfig: string; out Downloader: TDownloader): boolean;
  // Note: Cannot use JSON parser, because the object contains JS events.
  // The correct decoding should be:
  //   1. Locate the "playlist" object and read its "url" and "urlResolvers"
  //   2. Locate the resolver object identified by urlResolvers
  //   3. Read the resolver's "urlPattern"
  //   4. Find the name of the best bitrate in the resolver's "bitrates" array
  //   5. Build the final URL from urlPattern by replacing {0} with url and {1} with bitrate-name.

  function Unquote(const s: string): string;
    begin
      if s = '' then
        Result := s
      else if s[1] = '"' then
        Result := Copy(s, 2, Length(s)-2)
      else
        Result := s;
    end;

var
  Url, Path, ResolverID, UrlPattern: string;
begin
  Result := False;
  {$IFDEF DIRTYHACKS}
  if DecryptedConfig <> '' then
    if GetRegExpVarPairs(JSONConfigRegExp, DecryptedConfig, ['url', 'urlResolvers', 'urlPattern'], [@Path, @ResolverID, @UrlPattern]) then
      begin
      Path := Unquote(Path);
      ResolverID := Unquote(ResolverID);
      UrlPattern := Unquote(UrlPattern);
      if (Path <> '') and (ResolverID <> '') and (UrlPattern <> '') then
        begin
        Url := JSDecode(UrlPattern);
        Url := StringReplace(Url, '{1}', '1', [rfReplaceAll]);
        Url := StringReplace(Url, '{0}', JSDecode(Path), [rfReplaceAll]);
        if IsHttpProtocol(Url) then
          begin
          Downloader := THttpDirectDownloader.Create(Url);
          Result := True;
          end;
        end;
      end;
  {$ENDIF}
end;

{ TDownloader_Voyo_RTMP }

class function TDownloader_Voyo_RTMP.Features: TDownloaderFeatures;
begin
  Result := inherited Features + [dfPreferRtmpLiveStream];
end;

end.
