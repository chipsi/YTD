unit uStreamDownloader;
{.DEFINE XMLINFO}

interface

uses
  SysUtils, Classes, Windows,
  HttpSend, PCRE,
  uDownloader, uCommonDownloader;

type
  TStreamDownloader = class(TCommonDownloader)
    private
      MovieParamsRegExp: IRegEx;
      MovieIdFromParamsRegExp: IRegEx;
      MovieCdnIdFromParamsRegExp: IRegEx;
    protected
      function BeforePrepareFromPage(var Page: string; Http: THttpSend): boolean; override;
      function AfterPrepareFromPage(var Page: string; Http: THttpSend): boolean; override;
      function GetMovieInfoUrl: string; override;
      function GetFileNameExt: string; override;
      function GetProvider: string; override;
      function GetMovieInfoUrlForID(const ID: string): string; virtual;
    public
      constructor Create(const AMovieID: string); override;
      destructor Destroy; override;
    end;

implementation

uses
  {$IFDEF XMLINFO}
  janXmlParser2,
  {$ENDIF}
  uStringUtils;

const MOVIE_TITLE_REGEXP = '<title>(?P<TITLE>.*?)\s+-[^<-]+</title>';
const MOVIE_PARAMS_REGEXP = '<param\s+name="flashvars"\s+value="(?P<PARAM>.*?)"|\swriteSWF\s*\((?P<PARAM2>.*?)\)\s*;';
const MOVIE_ID_FROM_PARAMS_REGEXP = '[&'']id=(?P<ID>[0-9]+)';
const MOVIE_CDNID_FROM_PARAMS_REGEXP = '[&'']cdnID=(?P<ID>[0-9]+)';

{ TStreamDownloader }

constructor TStreamDownloader.Create(const AMovieID: string);
begin
  inherited Create(AMovieID);
  MovieTitleRegExp := RegExCreate(MOVIE_TITLE_REGEXP, [rcoIgnoreCase]);
  MovieParamsRegExp := RegExCreate(MOVIE_PARAMS_REGEXP, [rcoIgnoreCase, rcoSingleLine]);
  MovieIdFromParamsRegExp := RegExCreate(MOVIE_ID_FROM_PARAMS_REGEXP, [rcoIgnoreCase]);
  MovieCdnIdFromParamsRegExp := RegExCreate(MOVIE_CDNID_FROM_PARAMS_REGEXP, [rcoIgnoreCase]);
end;

destructor TStreamDownloader.Destroy;
begin
  MovieTitleRegExp := nil;
  MovieParamsRegExp := nil;
  MovieIdFromParamsRegExp := nil;
  MovieCdnIdFromParamsRegExp := nil;
  inherited;
end;

function TStreamDownloader.GetProvider: string;
begin
  Result := 'Stream.cz';
end;

function TStreamDownloader.GetMovieInfoUrlForID(const ID: string): string;
begin
  Result := 'http://www.stream.cz/video/' + ID;
end;

function TStreamDownloader.GetMovieInfoUrl: string;
begin
  Result := GetMovieInfoUrlForID(MovieID);
end;

function TStreamDownloader.BeforePrepareFromPage(var Page: string; Http: THttpSend): boolean;
begin
  Result := inherited BeforePrepareFromPage(Page, Http);
  Page := WideToAnsi(Utf8ToWide(Page));
end;

function TStreamDownloader.AfterPrepareFromPage(var Page: string; Http: THttpSend): boolean;
var {$IFDEF XMLINFO}
    IDMatch: IMatch;
    ID, Info: string;
    Xml: TjanXmlParser2;
    TitleNode, ContentNode: TjanXmlNode2;
    {$ENDIF}
    ParamMatch, CdnIDMatch: IMatch;
    Params, CdnID: string;
begin
  inherited AfterPrepareFromPage(Page, Http);
  Result := False;
  ParamMatch := MovieParamsRegExp.Match(Page);
  if ParamMatch.Matched then
    begin
    Params := ParamMatch.Groups.ItemsByName['PARAM'].Value;
    if Params = '' then
      Params := ParamMatch.Groups.ItemsByName['PARAM2'].Value;
    CdnIDMatch := MovieCdnIdFromParamsRegExp.Match(Params);
    if CdnIDMatch.Matched then
      begin
      CdnID := CdnIDMatch.Groups.ItemsByName['ID'].Value;
      if CdnID <> '' then
        begin
        {$IFDEF XMLINFO}
        IDMatch := MovieIdFromParamsRegExp.Match(Params);
        if IDMatch.Matched then
          try
            ID := IDMatch.Groups.ItemsByName['ID'].Value;
            if ID <> '' then
              if DownloadPage(Http, 'http://flash.stream.cz/get_info/' + ID, Info) then
                begin
                Info := WideToAnsi(Utf8ToWide(Info));
                Xml := TjanXmlParser2.create;
                try
                  Xml.xml := Info;
                  TitleNode := Xml.getChildByPath('video/title');
                  if TitleNode <> nil then
                    SetName(WideToAnsi(Utf8ToWide(TitleNode.text)));
                finally
                  Xml.Free;
                  end;
                end;
          except
            ;
          end;
        {$ENDIF}
        MovieURL := 'http://cdn-dispatcher.stream.cz/?id=' + CdnID;
        Result := True;
        SetPrepared(True);
        end;
      end;
    end;
end;

function TStreamDownloader.GetFileNameExt: string;
begin
  Result := '.flv';
end;

end.
