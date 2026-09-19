unit uFileSourceListOperation;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  uFileSourceOperation,
  uFileSourceOperationTypes,
  uFile,
  uFileSource;

type

  {en
     Called from the operation's own thread while files are still being
     listed, at most every ListProgressInterval milliseconds. The handler may
     read Files (the list gathered so far) but must not keep references to it.
  }
  TListProgressEvent = procedure(Sender: TObject) of object;

  { TFileSourceListOperation }

  TFileSourceListOperation = class(TFileSourceOperation)

  private
    FFileSource: IFileSource;
    FPath: String;
    FOnProgress: TListProgressEvent;
    FLastProgressTick: QWord;

  protected
    FFiles: TFiles;
    FFlatView: Boolean;
    FFlatViewDirs: Boolean;

    function GetFiles: TFiles;
    function GetID: TFileSourceOperationType; override;

    procedure UpdateStatisticsAtStartTime; override;

    {en
       Implementations call this after adding each file to FFiles so that
       progressive (partial) listing can be reported to the listener.
       Cheap when no listener is assigned.
    }
    procedure CheckProgress;

    property FileSource: IFileSource read FFileSource;

  public
    constructor Create(aFileSource: IFileSource; aPath: String); virtual reintroduce;
    destructor Destroy; override;

    function GetDescription(Details: TFileSourceOperationDescriptionDetails): String; override;

    // Retrieves files and revokes ownership of TFiles list.
    // The result of this function should be freed by the caller.
    function ReleaseFiles: TFiles;

    property Files: TFiles read GetFiles;
    property Path: String read FPath;
    property FlatView: Boolean write FFlatView;
    property FlatViewDirs: Boolean write FFlatViewDirs;
    property OnProgress: TListProgressEvent read FOnProgress write FOnProgress;

  end;

const
  // Minimum time between two OnProgress calls.
  ListProgressInterval = 100; // ms

implementation

uses
  uLng;

procedure TFileSourceListOperation.CheckProgress;
var
  ATick: QWord;
begin
  if not Assigned(FOnProgress) then Exit;
  // Only look at the clock every 16 files.
  if (FFiles.Count and 15) <> 0 then Exit;
  ATick := GetTickCount64;
  if FLastProgressTick = 0 then
    FLastProgressTick := ATick   // first call: start the interval, don't fire yet
  else if ATick - FLastProgressTick >= ListProgressInterval then
  begin
    FLastProgressTick := ATick;
    FOnProgress(Self);
    // The listener may have spent a long time; restart the interval after it.
    FLastProgressTick := GetTickCount64;
  end;
end;

constructor TFileSourceListOperation.Create(aFileSource: IFileSource; aPath: String);
begin
  FFileSource := aFileSource;
  FPath := aPath;
  inherited Create(FFileSource);
end;

destructor TFileSourceListOperation.Destroy;
begin
  inherited Destroy;

  if Assigned(FFiles) then
    FreeAndNil(FFiles);
end;

function TFileSourceListOperation.GetDescription(Details: TFileSourceOperationDescriptionDetails): String;
begin
  case Details of
    fsoddJobAndTarget:
      Result := Format(rsOperListingIn, [Path]);
    else
      Result := rsOperListing;
  end;
end;

function TFileSourceListOperation.GetID: TFileSourceOperationType;
begin
  Result := fsoList;
end;

function TFileSourceListOperation.GetFiles: TFiles;
begin
  Result := FFiles;
end;

function TFileSourceListOperation.ReleaseFiles: TFiles;
begin
  Result := FFiles;
  FFiles := nil; // revoke ownership
end;

procedure TFileSourceListOperation.UpdateStatisticsAtStartTime;
begin
  // Empty.
end;

end.

