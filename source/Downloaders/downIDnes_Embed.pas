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

unit downIDnes_Embed;
{$INCLUDE 'ytd.inc'}

interface

uses
  SysUtils, Classes,
  uPCRE, uXml, HttpSend,
  uDownloader, uCommonDownloader, uNestedDownloader,
  uRtmpDirectDownloader, uHttpDirectDownloader;

type
  TDownloader_IDnes_Embed = class(TNestedDownloader)
    private
    protected
      function GetMovieInfoUrl: string; override;
      function GetFileNameExt: string; override;
      function IdentifyDownloader(var Page: string; PageXml: TXmlDoc; Http: THttpSend; out Downloader: TDownloader): boolean; override;
    public
      class function Provider: string; override;
      class function UrlRegExp: string; override;
      constructor Create(const AMovieID: string); override;
      destructor Destroy; override;
    end;

implementation

uses
  uStringConsts,
  uStrings,
  uFunctions,
  uMessages,
  uDownloadClassifier;

// http://servis.idnes.cz/stream/flv/data.asp?idvideo=V110523_130926_tv-spolecnost_zkl&reklama=1&idrubriky=hobby-zahrada&idostrova=hobby&idclanku=A110523_110238_hobby-zahrada_mce
const
  URLREGEXP_BEFORE_ID = '';
  URLREGEXP_ID =        REGEXP_COMMON_URL_PREFIX + 'servi[sx]\.idnes\.cz/(?:media/video\.aspx?|stream/flv/data\.asp)\?.+';
  URLREGEXP_AFTER_ID =  '';

type
  TDownloader_iDnes_HTTP = class(THttpDirectDownloader);
  TDownloader_iDnes_RTMP = class(TRtmpDirectDownloader);

{ TDownloader_IDnes_Embed }

class function TDownloader_IDnes_Embed.Provider: string;
begin
  Result := 'iDnes.cz';
end;

class function TDownloader_IDnes_Embed.UrlRegExp: string;
begin
  Result := Format(REGEXP_BASE_URL, [URLREGEXP_BEFORE_ID, MovieIDParamName, URLREGEXP_ID, URLREGEXP_AFTER_ID]);
end;

constructor TDownloader_IDnes_Embed.Create(const AMovieID: string);
begin
  inherited;
  InfoPageEncoding := peXml;
  InfoPageIsXml := True;
end;

destructor TDownloader_IDnes_Embed.Destroy;
begin
  inherited;
end;

function TDownloader_IDnes_Embed.GetMovieInfoUrl: string;
begin
  Result := MovieID;
end;

function TDownloader_IDnes_Embed.GetFileNameExt: string;
begin
  Result := '.mp4';
end;

function TDownloader_IDnes_Embed.IdentifyDownloader(var Page: string; PageXml: TXmlDoc; Http: THttpSend; out Downloader: TDownloader): boolean;
var
  ItemType, Server, Path, VideoFile, Title, Stream: string;
  Items: TXmlNode;
  i: integer;
begin
  Result := False;
  if not XmlNodeByPath(PageXml, 'items', Items) then
    SetLastErrorMsg(ERR_INVALID_MEDIA_INFO_PAGE)
  else
    begin
    for i := 0 to Pred(Items.NodeCount) do
      if string(Items.Nodes[i].Name) = 'item' then
        if GetXmlVar(Items.Nodes[i], 'type', ItemType) then
          if ItemType = 'video' then
            begin
            if not GetXmlVar(Items.Nodes[i], 'linkvideo/server', Server) then
              SetLastErrorMsg(Format(ERR_VARIABLE_NOT_FOUND , ['server']))
            else
            if not GetXmlVar(Items.Nodes[i], 'linkvideo/path', Path) then
              SetLastErrorMsg(Format(ERR_VARIABLE_NOT_FOUND , ['path']))
            else if not GetXmlVar(Items.Nodes[i], 'linkvideo/file', VideoFile) then
              SetLastErrorMsg(Format(ERR_VARIABLE_NOT_FOUND , ['file']))
            else if not GetXmlVar(Items.Nodes[i], 'title', Title) then
              SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_TITLE)
            else if IsHttpProtocol(Server) then
              begin
              Downloader := TDownloader_iDnes_HTTP.CreateWithName(Server + Path + VideoFile, Title);
              Result := True;
              end
            else
              begin
              Stream := 'mp4:' + Path + VideoFile;
              Downloader := TDownloader_iDnes_RTMP.CreateWithName('rtmpt://' + Server + Stream, Title);
              TDownloader_iDnes_RTMP(Downloader).Playpath := Stream;
              TDownloader_iDnes_RTMP(Downloader).PageUrl := GetMovieInfoUrl;
              TDownloader_iDnes_RTMP(Downloader).SaveRtmpDumpOptions;
              Result := True;
              end;
            Exit;
            end;
    SetLastErrorMsg(ERR_INVALID_MEDIA_INFO_PAGE)
    end;
end;

initialization
  RegisterDownloader(TDownloader_IDnes_Embed);

end.
