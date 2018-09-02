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

unit downEuroGamer;
{$INCLUDE 'ytd.inc'}

interface

uses
  SysUtils, Classes,
  uPCRE, uXml, HttpSend,
  uDownloader, uCommonDownloader, uHttpDownloader;

type
  TDownloader_EuroGamer = class(THttpDownloader)
    private
    protected
      MovieIDRegExp: TRegExp;
      MovieUrlFromInfoRegExp: TRegExp;
      SubtitlesRegExp: TRegExp;
      MediaInfo: string;
    protected
      function GetMovieInfoUrl: string; override;
      function AfterPrepareFromPage(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean; override;
    public
      class function Provider: string; override;
      class function Features: TDownloaderFeatures; override;
      class function UrlRegExp: string; override;
      constructor Create(const AMovieID: string); override;
      destructor Destroy; override;
      {$IFDEF SUBTITLES}
      function ReadSubtitles(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean; override;
      {$ENDIF}
    end;

implementation

uses
  {$IFDEF SUBTITLES}
  uSubtitles,
  {$ENDIF}
  uStringConsts,
  uDownloadClassifier,
  uMessages;

// http://www.eurogamer.cz/videos/elder-scrolls-v-skyrim-video?size=hd
const
  URLREGEXP_BEFORE_ID = 'eurogamer\.cz/';
  URLREGEXP_ID =        REGEXP_SOMETHING;
  URLREGEXP_AFTER_ID =  '';

const
  REGEXP_MOVIE_TITLE =  REGEXP_TITLE_H1_CLASS;
  REGEXP_MOVIE_ID = '\.addVariable\s*\(\s*"playlist_id"\s*,\s*"(?P<ID>[0-9]+)"';
  REGEXP_MOVIE_URL = '(?:^|&)file(?:\[[^\]]*\])?=(?P<URL>https?[^&]+)';
  REGEXP_SUBTITLES = '(?<=^|&)sub_[0-9]+\[[^\]]*\]=(?P<CAPTION>[^&]*)&sub_start_[0-9]+\[[^\]]*\]=(?P<START>[0-9.]+)&sub_end_[0-9]+\[[^\]]*\]=(?P<END>[0-9.]+)(?=&|$)';

{ TDownloader_EuroGamer }

class function TDownloader_EuroGamer.Provider: string;
begin
  Result := 'EuroGamer.cz';
end;

class function TDownloader_EuroGamer.Features: TDownloaderFeatures;
begin
  Result := inherited Features + [
    {$IFDEF SUBTITLES} dfSubtitles {$ENDIF}
    ];
end;

class function TDownloader_EuroGamer.UrlRegExp: string;
begin
  Result := Format(REGEXP_COMMON_URL, [URLREGEXP_BEFORE_ID, MovieIDParamName, URLREGEXP_ID, URLREGEXP_AFTER_ID]);
end;

constructor TDownloader_EuroGamer.Create(const AMovieID: string);
begin
  inherited;
  InfoPageEncoding := peUtf8;
  MovieTitleRegExp := RegExCreate(Format(REGEXP_MOVIE_TITLE, ['title']));
  MovieIDRegExp := RegExCreate(REGEXP_MOVIE_ID);
  SubtitlesRegExp := RegExCreate(REGEXP_SUBTITLES);
  MovieUrlFromInfoRegExp := RegExCreate(REGEXP_MOVIE_URL);
end;

destructor TDownloader_EuroGamer.Destroy;
begin
  RegExFreeAndNil(MovieTitleRegExp);
  RegExFreeAndNil(MovieIDRegExp);
  RegExFreeAndNil(SubtitlesRegExp);
  RegExFreeAndNil(MovieUrlFromInfoRegExp);
  inherited;
end;

function TDownloader_EuroGamer.GetMovieInfoUrl: string;
begin
  Result := 'http://www.eurogamer.cz/' + MovieID;
end;

function TDownloader_EuroGamer.AfterPrepareFromPage(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean;
var ID, Url: string;
begin
  inherited AfterPrepareFromPage(Page, PageXml, Http);
  Result := False;
  MediaInfo := '';
  if not GetRegExpVar(MovieIDRegExp, Page, 'ID', ID) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_INFO_PAGE)
  else if not DownloadPage(Http, Format('http://www.eurogamer.cz/get_pls.php?playlist_id=%s&profile_id=hd&r=957&player_mode=normal', [ID]), MediaInfo) then
    SetLastErrorMsg(ERR_FAILED_TO_DOWNLOAD_MEDIA_INFO_PAGE)
  else if not GetRegExpVar(MovieUrlFromInfoRegExp, MediaInfo, 'URL', Url) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_URL)
  else
    begin
    MovieUrl := UrlDecode(Url);
    SetPrepared(True);
    Result := True;
    end;
end;

{$IFDEF SUBTITLES}
function TDownloader_EuroGamer.ReadSubtitles(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean;
const
  ONE_SECOND = 1/(24*60*60);
var
  n: integer;
  Sub: string;
  SubStart, SubEnd: TDateTime;
begin
  Result := False;
  fSubtitles := '';
  fSubtitlesExt := '';
  n := 0;
  if MediaInfo <> '' then
    if SubtitlesRegExp.Match(MediaInfo) then
      try
        repeat
          Sub := HtmlDecode(UrlDecode(SubtitlesRegExp.SubexpressionByName('CAPTION')), True);
          SubStart := StrToFloat(StringReplace(SubtitlesRegExp.SubexpressionByName('START'), '.', DecimalSeparator, []));
          SubEnd := StrToFloat(StringReplace(SubtitlesRegExp.SubexpressionByName('END'), '.', DecimalSeparator, []));
          fSubtitles := fSubtitles + {$IFDEF UNICODE} AnsiString {$ENDIF} (SubtitlesToSrt(n, SubStart*ONE_SECOND, SubEnd*ONE_SECOND, Sub));
        until not SubtitlesRegExp.MatchAgain;
        fSubtitlesExt := '.srt';
        Result := fSubtitles <> '';
      except
        Result := False;
        end;
end;
{$ENDIF}

initialization
  RegisterDownloader(TDownloader_EuroGamer);

end.
