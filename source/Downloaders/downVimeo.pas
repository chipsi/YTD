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

unit downVimeo;
{$INCLUDE 'ytd.inc'}

interface

uses
  SysUtils, Classes,
  uPCRE, uXml, HttpSend,
  uDownloader, uCommonDownloader, uHttpDownloader;

type
  TDownloader_Vimeo = class(THttpDownloader)
    private
    protected
      ConfigRegExp: TRegExp;
      ConfigVarsRegExp: TRegExp;
    protected
      function GetFileNameExt: string; override;
      function GetMovieInfoUrl: string; override;
      function GetMovieInfoContent(Http: THttpSend; Url: string; out Page: string; out Xml: TXmlDoc; Method: THttpMethod = hmGET): boolean; override;
      function AfterPrepareFromPage(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean; override;
    public
      class function Provider: string; override;
      class function UrlRegExp: string; override;
      constructor Create(const AMovieID: string); override;
      destructor Destroy; override;
    end;

implementation

uses
  uStringConsts,
  uDownloadClassifier,
  uMessages;

// http://www.vimeo.com/10777111
const
  URLREGEXP_BEFORE_ID = '^https?://(?:[a-z0-9-]+\.)*(?<!\bplayer\.)vimeo\.com/(?:video/)?';
  URLREGEXP_ID =        '[0-9]+';
  URLREGEXP_AFTER_ID =  '';

const
  REGEXP_MOVIE_TITLE = REGEXP_TITLE_H1;
  REGEXP_CONFIG = '\{\s*"request"\s*:\s*\{(?P<CONFIG>.*?)\}';
  REGEXP_CONFIG_VARS = '"(?P<VARNAME>[^"]+)"\s*:\s*(?P<QUOTE>"?)(?P<VARVALUE>.*?)(?P=QUOTE)\s*,';

{ TDownloader_Vimeo }

class function TDownloader_Vimeo.Provider: string;
begin
  Result := 'Vimeo.com';
end;

class function TDownloader_Vimeo.UrlRegExp: string;
begin
  Result := Format(URLREGEXP_BEFORE_ID + '(?P<%s>' + URLREGEXP_ID + ')' + URLREGEXP_AFTER_ID, [MovieIDParamName]);;
end;

constructor TDownloader_Vimeo.Create(const AMovieID: string);
begin
  inherited Create(AMovieID);
  MovieTitleRegExp := RegExCreate(REGEXP_MOVIE_TITLE);
  ConfigRegExp := RegExCreate(REGEXP_CONFIG);
  ConfigVarsRegExp := RegExCreate(REGEXP_CONFIG_VARS);
  InfoPageEncoding := peUTF8;
end;

destructor TDownloader_Vimeo.Destroy;
begin
  RegExFreeAndNil(MovieTitleRegExp);
  RegExFreeAndNil(ConfigRegExp);
  RegExFreeAndNil(ConfigVarsRegExp);
  inherited;
end;

function TDownloader_Vimeo.GetFileNameExt: string;
begin
  Result := '.mp4';
end;

function TDownloader_Vimeo.GetMovieInfoUrl: string;
begin
  Result := 'http://vimeo.com/' + MovieID;
end;

function TDownloader_Vimeo.GetMovieInfoContent(Http: THttpSend; Url: string; out Page: string; out Xml: TXmlDoc; Method: THttpMethod): boolean;
begin
  Http.Cookies.Add('hd_preference=1');
  Result := inherited GetMovieInfoContent(Http, Url, Page, Xml, Method);
end;

function TDownloader_Vimeo.AfterPrepareFromPage(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean;
const
  QualityStr: array[0..1] of string = ('hd', 'sd');
var
  Config, Signature, Timestamp, Url: string;
  i: integer;
begin
  inherited AfterPrepareFromPage(Page, PageXml, Http);
  Result := False;
  if not GetRegExpVar(ConfigRegExp, Page, 'CONFIG', Config) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_EMBEDDED_OBJECT)
  else if not GetRegExpVarPairs(ConfigVarsRegExp, Config, ['signature', 'timestamp'], [@Signature, @Timestamp]) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_EMBEDDED_OBJECT)
  else if Signature = '' then
    SetLastErrorMsg(Format(ERR_VARIABLE_NOT_FOUND, ['signature']))
  else if Timestamp = '' then
    SetLastErrorMsg(Format(ERR_VARIABLE_NOT_FOUND, ['timestamp']))
  else
    begin
    Url := 'http://player.vimeo.com/play_redirect?clip_id=' + MovieID + '&sig=' + Signature + '&time=' + Timestamp + '&quality=%s&codecs=H264,VP8,VP6&type=moogaloop_local&embed_location=';
    MovieUrl := Format(Url, [QualityStr[0]]);
    for i := 0 to Pred(Length(QualityStr)) do
      if DownloadPage(Http, Format(Url, [QualityStr[i]]), hmHEAD) then
        begin
        MovieUrl := Format(Url, [QualityStr[i]]);
        Result := True;
        SetPrepared(True);
        end;
    end;
end;

initialization
  RegisterDownloader(TDownloader_Vimeo);

end.
