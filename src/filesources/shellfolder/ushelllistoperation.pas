unit uShellListOperation;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  Windows, ShlObj, ComObj,
  uFileSourceListOperation,
  uShellFileSource,
  uFileSource;

type

  { TShellListOperation }

  TShellListOperation = class(TFileSourceListOperation)
  private
    FShellFileSource: IShellFileSource;
    procedure ListFolder(AFolder: IShellFolder2; grfFlags: DWORD);
    procedure ListDrives;
    procedure ListDirectory;
  public
    constructor Create(aFileSource: IFileSource; aPath: String); override;
    procedure MainExecute; override;
  end;

implementation

uses
  ActiveX, Variants, SyncObjs, JwaWinNetWk, DCOSUtils, DCDateTimeUtils, ShellAPI,
  DCStrUtils, DCConvertEncoding, uOSUtils, uFile, uShellFolder, uShlObjAdditional,
  uShowMsg, uShellFileSourceUtil;

const
  // How long ListDrives waits for network drive capacity queries before
  // showing the listing without them. Only ever paid when a drive the
  // redirector considers connected does not answer (e.g. a sleeping VPN
  // peer); healthy shares answer in well under 100 ms.
  CAPACITY_TIMEOUT = 1000;

const
  // Missing from the FPC Windows unit; GetDriveType returns this for
  // disconnected mapped network drives (among others).
  DRIVE_NO_ROOT_PATH = 1;

type

  { TDriveCapacityThread }

  {en
     Queries a drive's capacity in a separate thread: on a disconnected
     network drive the query blocks until the SMB timeout (tens of seconds),
     which must not stall the whole "This PC" listing. Same abandon pattern
     as TNetworkThread: the caller waits for FDone with a deadline, always
     signals FRelease, and the thread frees itself whenever the blocked
     API call finally returns.
  }
  TDriveCapacityThread = class(TThread)
  private
    FRoot: String;
    FSize: Int64;
    FValid: Boolean;
    FDone: TSimpleEvent;
    FRelease: TSimpleEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(const ARoot: String);
    destructor Destroy; override;
  end;

procedure TDriveCapacityThread.Execute;
var
  AFree: Int64 = 0;
  ATotal: Int64 = 0;
begin
  FValid:= uOSUtils.GetDiskFreeSpace(FRoot, AFree, ATotal);
  FSize:= ATotal;
  FDone.SetEvent;
  FRelease.WaitFor(INFINITE);
end;

constructor TDriveCapacityThread.Create(const ARoot: String);
begin
  FRoot:= ARoot;
  FDone:= TSimpleEvent.Create;
  FRelease:= TSimpleEvent.Create;
  inherited Create(False);
  FreeOnTerminate:= True;
end;

destructor TDriveCapacityThread.Destroy;
begin
  FDone.Free;
  FRelease.Free;
  inherited Destroy;
end;

{en
   @true when ARoot ("X:\") is a mapped network drive whose connection the
   redirector currently considers alive. Purely local (MPR state table, what
   "net use" shows) - never touches the network. Note a disconnected mapped
   drive reports DRIVE_NO_ROOT_PATH, not DRIVE_REMOTE.
}
function MappedDriveConnected(const ARoot: String): Boolean;
var
  ALen: DWORD;
  ARemote: array[0..1023] of WideChar;
begin
  ALen:= Length(ARemote);
  case WNetGetConnectionW(PWideChar(CeUtf8ToUtf16(ExcludeTrailingBackslash(ARoot))),
                          ARemote, ALen) of
    NO_ERROR, ERROR_MORE_DATA: Result:= True;
  else
    Result:= False;
  end;
end;

{en
   Remote names ("\\server\share") of the currently connected - not merely
   remembered - network resources, read from the local MPR table
   (WNetOpenEnum(RESOURCE_CONNECTED)); never touches the network.
}
function GetConnectedRemoteNames: TStringList;
var
  I: Integer;
  hEnum: THandle;
  NR: PNetResourceW;
  ACount, ASize: DWORD;
  ABuffer: array[0..16383] of Byte;
begin
  Result:= TStringList.Create;
  Result.CaseSensitive:= False;
  if WNetOpenEnumW(RESOURCE_CONNECTED, RESOURCETYPE_DISK, 0, nil, {%H-}hEnum) <> NO_ERROR then
    Exit;
  try
    repeat
      ACount:= DWORD(-1);
      ASize:= SizeOf(ABuffer);
      if WNetEnumResourceW(hEnum, ACount, @ABuffer[0], ASize) <> NO_ERROR then Break;
      NR:= @ABuffer[0];
      for I:= 1 to ACount do
      begin
        if Assigned(NR^.lpRemoteName) then
          Result.Add(ExcludeTrailingBackslash(CeUtf16ToUtf8(UnicodeString(NR^.lpRemoteName))));
        Inc(NR);
      end;
    until False;
  finally
    WNetCloseEnum(hEnum);
  end;
end;

{ TShellListOperation }

procedure TShellListOperation.ListFolder(AFolder: IShellFolder2; grfFlags: DWORD);
const
  SFGAOF_DEFAULT = SFGAO_STORAGE or SFGAO_HIDDEN or SFGAO_FOLDER;
var
  AFile: TFile;
  PIDL: PItemIDList;
  AValue: OleVariant;
  rgfInOut: LongWord;
  AParent: PItemIDList;
  NumIDs: LongWord = 0;
  EnumIDList: IEnumIDList;
begin
  OleCheckUTF8(SHGetIDListFromObject(AFolder, AParent));
  try
    OleCheckUTF8(AFolder.EnumObjects(0, grfFlags, EnumIDList));

    while EnumIDList.Next(1, PIDL, NumIDs) = S_OK do
    try
      CheckOperationState;

      aFile:= TShellFileSource.CreateFile(Path);

      AFile.Name:= GetDisplayNameEx(AFolder, PIDL, SHGDN_INFOLDER);
      TFileShellProperty(AFile.LinkProperty).Item:= ILCombine(AParent, PIDL);
      AFile.LinkProperty.LinkTo:= GetDisplayName(AFolder, PIDL, SHGDN_INFOLDER or SHGDN_FORPARSING);

      rgfInOut:= SFGAOF_DEFAULT;

      if Succeeded(AFolder.GetAttributesOf(1, PIDL, rgfInOut)) then
      begin
        if (rgfInOut and SFGAO_STORAGE <> 0) then
        begin
          AFile.Attributes:= FILE_ATTRIBUTE_DEVICE or FILE_ATTRIBUTE_VIRTUAL;
        end;
        if (rgfInOut and SFGAO_FOLDER <> 0) then
        begin
          AFile.Attributes:= AFile.Attributes or FILE_ATTRIBUTE_DIRECTORY;
        end;
        if (rgfInOut and SFGAO_HIDDEN <> 0) then
        begin
          AFile.Attributes:= AFile.Attributes or FILE_ATTRIBUTE_HIDDEN;
        end;
      end;

      AValue:= GetDetails(AFolder, PIDL, SCID_FileSize);
      if VarIsOrdinal(AValue) then
        AFile.Size:= AValue
      else if AFile.IsDirectory then
        AFile.Size:= 0
      else begin
        AFile.SizeProperty.IsValid:= False;
      end;

      AValue:= GetDetails(AFolder, PIDL, SCID_DateModified);
      if AValue <> Unassigned then
        AFile.ModificationTime:= AValue
      else begin
        AFile.ModificationTimeProperty.IsValid:= False;
      end;

      AValue:= GetDetails(AFolder, PIDL, SCID_DateCreated);
      if AValue <> Unassigned then
        AFile.CreationTime:= AValue
      else begin
        AFile.CreationTimeProperty.IsValid:= False;
      end;

      FFiles.Add(AFile);
    finally
      CoTaskMemFree(PIDL);
    end;
  finally
    CoTaskMemFree(AParent);
  end;
end;

procedure TShellListOperation.ListDrives;
const
  SFGAOF_DEFAULT = SFGAO_FILESYSTEM or SFGAO_FOLDER;
type
  TPendingCapacity = record
    AFile: TFile;
    AThread: TDriveCapacityThread;
  end;
var
  AFile: TFile;
  LinkTo: String;
  PIDL: PItemIDList;
  rgfInOut: LongWord;
  AValue: OleVariant;
  NumIDs: LongWord = 0;
  AFolder: IShellFolder2;
  EnumIDList: IEnumIDList;
  DrivesPIDL: PItemIDList;
  DesktopFolder: IShellFolder;
  Pending: array of TPendingCapacity;
  IsNet, IsConnected: Boolean;
  ConnectedNames: TStringList;

  procedure CollectCapacities;
  var
    J: Integer;
    ARemain: Int64;
    ADeadline: QWord;
  begin
    ADeadline:= GetTickCount64 + CAPACITY_TIMEOUT;
    for J:= 0 to High(Pending) do
    with Pending[J] do
    begin
      ARemain:= Int64(ADeadline) - Int64(GetTickCount64);
      if ARemain < 0 then ARemain:= 0;
      if (AThread.FDone.WaitFor(ARemain) = wrSignaled) and AThread.FValid then
        AFile.Size:= AThread.FSize
      else begin
        AFile.SizeProperty.IsValid:= False;
      end;
      // After this the thread frees itself - don't touch it again.
      AThread.FRelease.SetEvent;
    end;
  end;

begin
  Pending:= nil;
  ConnectedNames:= nil;
  OleCheckUTF8(SHGetDesktopFolder(DesktopFolder));
  OleCheckUTF8(SHGetFolderLocation(0, CSIDL_DRIVES, 0, 0, {%H-}DrivesPIDL));
  try
  try
    OleCheckUTF8(DesktopFolder.BindToObject(DrivesPIDL, nil, IID_IShellFolder2, Pointer(AFolder)));

    OleCheckUTF8(AFolder.EnumObjects(0, SHCONTF_FOLDERS or SHCONTF_STORAGE, EnumIDList));

    while EnumIDList.Next(1, PIDL, NumIDs) = S_OK do
    try
      CheckOperationState;

      LinkTo:= GetDisplayName(AFolder, PIDL, SHGDN_INFOLDER or SHGDN_FORPARSING);

      // Skip virtual folders
      if StrBegins(LinkTo, '::{') then Continue;

      aFile:= TShellFileSource.CreateFile(Path);

      AFile.LinkProperty.LinkTo:= LinkTo;
      AFile.Name:= GetDisplayNameEx(AFolder, PIDL, SHGDN_INFOLDER);
      TFileShellProperty(AFile.LinkProperty).Item:= ILCombine(DrivesPIDL, PIDL);

      rgfInOut:= SFGAOF_DEFAULT;
      AFile.Attributes:= FILE_ATTRIBUTE_DEVICE or FILE_ATTRIBUTE_VIRTUAL;

      if Succeeded(AFolder.GetAttributesOf(1, PIDL, rgfInOut)) then
      begin
        if (SFGAO_FILESYSTEM and rgfInOut) <> 0 then
        begin
          AFile.Attributes:= AFile.Attributes or FILE_ATTRIBUTE_NORMAL;
        end
        else if (rgfInOut and SFGAO_FOLDER <> 0) then
        begin
          AFile.Attributes:= AFile.Attributes or FILE_ATTRIBUTE_DIRECTORY;
        end;
      end;

      AFile.ModificationTimeProperty.IsValid:= False;

      // Querying the capacity of a network drive whose host is unreachable
      // blocks until the SMB timeout (tens of seconds) - even for a drive the
      // redirector already knows is unavailable, because touching it triggers
      // an auto-reconnect attempt. So: known-disconnected network drives are
      // not probed at all, connected ones (which can still hang - a mapping
      // can say OK while the host is dead) are queried in parallel threads
      // with a CAPACITY_TIMEOUT deadline, and only clearly local drives are
      // queried synchronously through the shell.
      // Mapped network drives have a UNC parsing name ("\\server\share"), not
      // a drive letter; disconnected letter-form drives report
      // DRIVE_NO_ROOT_PATH (not DRIVE_REMOTE).
      // Note: the in-folder parsing name of a drive is "X:" - no backslash.
      IsNet:= StrBegins(LinkTo, PathDelim + PathDelim);
      if (not IsNet) and (Length(LinkTo) in [2, 3]) and (LinkTo[2] = ':') then
      begin
        IsNet:= GetDriveTypeW(PWideChar(CeUtf8ToUtf16(IncludeTrailingBackslash(LinkTo)))) in
                [DRIVE_UNKNOWN, DRIVE_NO_ROOT_PATH, DRIVE_REMOTE];
      end;

      if IsNet then
      begin
        if not Assigned(ConnectedNames) then
          ConnectedNames:= GetConnectedRemoteNames;
        if StrBegins(LinkTo, PathDelim + PathDelim) then
          IsConnected:= ConnectedNames.IndexOf(ExcludeTrailingBackslash(LinkTo)) >= 0
        else begin
          IsConnected:= MappedDriveConnected(LinkTo);
        end;
        if IsConnected then
        begin
          SetLength(Pending, Length(Pending) + 1);
          Pending[High(Pending)].AFile:= AFile;
          Pending[High(Pending)].AThread:=
            TDriveCapacityThread.Create(IncludeTrailingBackslash(LinkTo));
        end
        else begin
          AFile.SizeProperty.IsValid:= False;
        end;
      end
      else begin
        AValue:= GetDetails(AFolder, PIDL, SCID_Capacity);
        if VarIsOrdinal(AValue) then
          AFile.Size:= AValue
        else if AFile.IsDirectory then
          AFile.Size:= 0
        else begin
          AFile.SizeProperty.IsValid:= False;
        end;
      end;

      FFiles.Add(AFile);
    finally
      CoTaskMemFree(PIDL);
    end;
  finally
    CoTaskMemFree(DrivesPIDL);
  end;
  finally
    CollectCapacities;
    ConnectedNames.Free;
  end;
end;

procedure TShellListOperation.ListDirectory;
var
  AFolder: IShellFolder2;
begin
  if Succeeded(FShellFileSource.FindFolder(ExcludeTrailingBackslash(Path), AFolder)) then
  begin
    ListFolder(AFolder, SHCONTF_FOLDERS or SHCONTF_NONFOLDERS or SHCONTF_INCLUDEHIDDEN);
  end;
end;

constructor TShellListOperation.Create(aFileSource: IFileSource;
  aPath: String);
begin
  FFiles := TFiles.Create(aPath);
  FShellFileSource:= aFileSource as IShellFileSource;
  inherited Create(aFileSource, aPath);
end;

procedure TShellListOperation.MainExecute;
begin
  FFiles.Clear;
  try
    if FShellFileSource.IsPathAtRoot(Path) then
      ListDrives
    else begin
      ListDirectory;
    end;
  except
    on E: Exception do msgError(Thread, E.Message);
  end;
end;

end.

