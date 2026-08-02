unit fQuickSearch;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, StdCtrls, LCLType,
  ExtCtrls, Buttons;

type
  TQuickSearchMode = (qsSearch, qsFilter, qsNone);
  {en
     Mode of the bar itself, selected by the first typed character
     (Directory Opus style find-as-you-type field):
     no prefix - find/filter as before, '>' - execute internal command,
     '/' or '~' - go to path (with alias support).
  }
  TQuickBarMode = (qbmSearch, qbmCommand, qbmGoTo);
  TQuickSearchDirection = (qsdNone, qsdFirst, qsdLast, qsdNext, qsdPrevious);
  TQuickSearchMatch = (qsmBeginning, qsmEnding);
  TQuickSearchCase = (qscSensitive, qscInsensitive);
  TQuickSearchItems = (qsiFiles, qsiDirectories, qsiFilesAndDirectories);
  TQuickSearchCancelMode = (qscmNode, qscmAtLeastOneThenCancelIfNoFound, qscmCancelIfNoFound);

  TQuickSearchOptions = record
    Match: set of TQuickSearchMatch;
    SearchCase: TQuickSearchCase;
    Items: TQuickSearchItems;
    Diacritics: Boolean;
    Direction: TQuickSearchDirection;
    LastSearchMode: TQuickSearchMode;
    CancelSearchMode: TQuickSearchCancelMode;
  end;

  TOnChangeSearch = procedure(Sender: TObject; ASearchText: String; const ASearchOptions: TQuickSearchOptions; InvertSelection: Boolean = False) of Object;
  TOnChangeFilter = procedure(Sender: TObject; AFilterText: String; const AFilterOptions: TQuickSearchOptions) of Object;
  TOnExecute = procedure(Sender: TObject) of Object;
  TOnHide = procedure(Sender: TObject) of Object;
  TOnGoToPath = procedure(Sender: TObject; const APath: String) of Object;

  { TfrmQuickSearch }

  TfrmQuickSearch = class(TFrame)
    btnCancel: TButton;
    edtSearch: TEdit;
    pnlOptions: TPanel;
    sbDiacritics: TSpeedButton;
    sbMatchBeginning: TSpeedButton;
    sbMatchEnding: TSpeedButton;
    sbCaseSensitive: TSpeedButton;
    sbFiles: TSpeedButton;
    sbDirectories: TSpeedButton;
    tglFilter: TToggleBox;
    procedure btnCancelClick(Sender: TObject);
    procedure edtSearchChange(Sender: TObject);
    procedure edtSearchKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure FrameExit(Sender: TObject);
    procedure sbDiacriticsClick(Sender: TObject);
    procedure sbCaseSensitiveClick(Sender: TObject);
    procedure sbFilesAndDirectoriesClick(Sender: TObject);
    procedure sbMatchBeginningClick(Sender: TObject);
    procedure sbMatchEndingClick(Sender: TObject);
    procedure tglFilterChange(Sender: TObject);
    procedure btnMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure btnCancelMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    Options: TQuickSearchOptions;
    Mode: TQuickSearchMode;
    Active: Boolean;
    FilterOptions: TQuickSearchOptions;
    FilterText: String;
    Finalizing: Boolean;
    FUpdateCount: Integer;
    FNeedsChangeSearch: Boolean;
    FIntendedLeave: Boolean;
    FBarMode: TQuickBarMode;
    FPrefixFilter: Boolean;
    FPendingCommand: String;
    lblMode: TLabel;
    lsCommands: TListBox;
    FCommandCache: TStringList;
    FCommandCaptions: TStringList;
    {en
       Value behind each visible dropdown row: command name in command
       mode, target path in go-to mode
    }
    FDropdownValues: TStringList;
    FDropdownPicked: Boolean;
    {en
       Detects the bar mode from the first character of the typed text
    }
    procedure UpdateBarMode;
    procedure UpdateModeLabel;
    {en
       Text to search/filter by, with the mode prefix stripped
    }
    function GetSearchableText: String;
    procedure EnsureCommandCache;
    procedure UpdateCommandList;
    procedure UpdateAliasList;
    {en
       Fills the dropdown with subdirectories of the directory typed so far
    }
    procedure UpdateDirectoryList;
    procedure ShowDropdown;
    procedure HideCommandList;
    procedure MoveCommandSelection(ADelta: Integer);
    procedure ExecuteSelectedCommand;
    procedure ExecutePendingCommand(Data: PtrInt);
    procedure lsCommandsDblClick(Sender: TObject);
    procedure DoGoToPath;
    {en
       Expands "~" and path aliases ("/name" -> aliased path)
    }
    function ResolveGoToPath(const S: String): String;
    {en
       Does the typed text mean "go to a path"?
    }
    function IsGoToText(const S: String): Boolean;
    {en
       Index of the first path separator at or after FromPos, 0 if none
    }
    function FindPathSeparator(const S: String; FromPos: Integer): Integer;
    procedure BeginUpdate;
    procedure CheckFilesOrDirectoriesDown;
    procedure EndUpdate;
    procedure DoHide;
    procedure DoOnChangeSearch;
    {en
       Loads control states from options values
    }
    procedure LoadControlStates;
    procedure PushFilter;
    procedure PopFilter;
    procedure ClearFilter;
    procedure CancelFilter;
    procedure SetFocus(Data: PtrInt);
    procedure RestoreFocus(Data: PtrInt);
    procedure ProcessParams(const SearchMode: TQuickSearchMode; const Params: array of String);
  public
    LimitedAutoHide: Boolean;
    OnChangeSearch: TOnChangeSearch;
    OnChangeFilter: TOnChangeFilter;
    OnExecute: TOnExecute;
    OnHide: TOnHide;
    OnGoToPath: TOnGoToPath;
    constructor Create(TheOwner: TWinControl); reintroduce;
    destructor Destroy; override;
    procedure CloneTo(AQuickSearch: TfrmQuickSearch);
    procedure Execute(SearchMode: TQuickSearchMode; const Params: array of String; Char: TUTF8Char = #0);
    procedure Reset;
    procedure Finalize;
    function CheckSearchOrFilter(var Key: Word): Boolean; overload;
    function CheckSearchOrFilter(var UTF8Key: TUTF8Char): Boolean; overload;
  end;

{en
   Allows to compare TQuickSearchOptions structures
}
  operator = (qsOptions1, qsOptions2: TQuickSearchOptions) CompareResult: Boolean;

implementation

uses
  Math, Graphics, LazUTF8, LCLIntf,
  DCOSUtils, DCStrUtils, uFindEx,
  uKeyboard,
  uGlobs,
  uLng,
  uSysFolders,
  uFormCommands,
  fMain, uMainCommands
{$IF DEFINED(LCLQT) or DEFINED(LCLQT5) or DEFINED(LCLQT6)}
  , uFileView
{$ENDIF}
{$IFDEF MSWINDOWS}
  , uShellFileSource
{$ENDIF}
  ;

const
{
  Parameters:

  "filter"           - set filtering (on/off/toggle)
  "search"           - set searching (on/off/cycle)
  "direction"        - jump to another match (first/last/next/previous);
                       given alone it only moves between matches, without
                       changing the current search/filter mode
  "matchbeginning"   - set match beginning option (on/off/toggle)
  "matchending"      - set match ending option (on/off/toggle)
  "casesensitive"    - set case sensitive searching (on/off/toggle)
  "files"            - set filtering files (on/off/toggle)
  "directories"      - set filtering directories (on/off/toggle)
  "filesdirectories" - toggle between files, directories and both (no value)
  "text"="<...>"     - set <...> as new text to search/filter (string)

  'toggle' switches between on and off
  'cycle' goto to next, next, next and so one
}
  // parameters for quick search / filter actions
  PARAMETER_FILTER                 = 'filter';
  PARAMETER_SEARCH                 = 'search';
  PARAMETER_DIRECTION              = 'direction';
  PARAMETER_MATCH_BEGINNING        = 'matchbeginning';
  PARAMETER_MATCH_ENDING           = 'matchending';
  PARAMETER_CASE_SENSITIVE         = 'casesensitive';
  PARAMETER_FILES                  = 'files';
  PARAMETER_DIRECTORIES            = 'directories';
  PARAMETER_FILES_DIRECTORIES      = 'filesdirectories';
  PARAMETER_TEXT                   = 'text';

  TOGGLE_VALUE = 'toggle';
  CYCLE_VALUE = 'cycle';
  FIRST_VALUE = 'first';
  LAST_VALUE = 'last';
  NEXT_VALUE = 'next';
  PREVIOUS_VALUE = 'previous';

  // bar mode prefixes (Directory Opus style find-as-you-type field)
  CMD_MODE_PREFIX    = '>';  // execute internal command
  PATH_MODE_PREFIX   = '/';  // go to path / path alias
  PATH_MODE_HOME     = '~';  // go to path relative to home directory
  FILTER_MODE_PREFIX = '*';  // switch into filter mode

  // characters accepted as path separators when splitting "/alias/subpath"
{$IFDEF MSWINDOWS}
  PATH_SEPARATORS = ['/', '\'];
{$ELSE}
  PATH_SEPARATORS = ['/'];
{$ENDIF}

  MAX_VISIBLE_COMMANDS = 10;

{$R *.lfm}

operator = (qsOptions1, qsOptions2: TQuickSearchOptions) CompareResult: Boolean;
begin
  Result := True;

  if qsOptions1.Match <> qsOptions2.Match then
    Result := False;

  if qsOptions1.Items <> qsOptions2.Items then
    Result := False;

  if qsOptions1.SearchCase <> qsOptions2.SearchCase then
    Result := False;

  if qsOptions1.Diacritics <> qsOptions2.Diacritics then
    Result := False;
end;

function GetBoolState(const Value: String; OldState: Boolean): Boolean;
begin
  if Value = TOGGLE_VALUE then
    Result := not OldState
  else if not GetBoolValue(Value, Result) then
    Result := OldState;
end;

{ TfrmQuickSearch }

constructor TfrmQuickSearch.Create(TheOwner: TWinControl);
begin
  inherited Create(TheOwner);

  Self.Parent := TheOwner;

  // load default options
  Options := gQuickSearchOptions;
  Options.LastSearchMode := qsNone;
  LoadControlStates;

  FilterOptions := gQuickSearchOptions;
  FilterText := EmptyStr;
  Finalizing := False;

  FBarMode := qbmSearch;

  // mode indicator to the left of the edit box
  lblMode := TLabel.Create(Self);
  lblMode.Parent := Self;
  lblMode.AutoSize := True;
  lblMode.Caption := EmptyStr;
  lblMode.Font.Style := [fsBold];
  lblMode.AnchorSideLeft.Control := Self;
  lblMode.AnchorSideTop.Control := edtSearch;
  lblMode.AnchorSideTop.Side := asrCenter;
  lblMode.BorderSpacing.Left := 4;
  edtSearch.AnchorSideLeft.Control := lblMode;
  edtSearch.AnchorSideLeft.Side := asrBottom;

  // command palette dropdown, shown above the bar in command mode
  lsCommands := TListBox.Create(Self);
  lsCommands.Parent := TheOwner;
  lsCommands.Visible := False;
  lsCommands.TabStop := False;
  lsCommands.OnDblClick := @lsCommandsDblClick;

  FDropdownValues := TStringList.Create;

  HotMan.Register(Self.edtSearch, 'Quick Search');
end;

destructor TfrmQuickSearch.Destroy;
begin
  if Assigned(HotMan) then
    HotMan.UnRegister(Self.edtSearch);

  Application.RemoveAsyncCalls(Self);
  FreeAndNil(FCommandCache);
  FreeAndNil(FCommandCaptions);
  FreeAndNil(FDropdownValues);

  inherited Destroy;
end;

procedure TfrmQuickSearch.CloneTo(AQuickSearch: TfrmQuickSearch);
var
  TempEvent: TNotifyEvent;
begin
  AQuickSearch.Active := Self.Active;
  AQuickSearch.Mode := Self.Mode;
  AQuickSearch.Options := Self.Options;
  AQuickSearch.LoadControlStates;
  AQuickSearch.FilterOptions := Self.FilterOptions;
  AQuickSearch.FilterText := Self.FilterText;
  TempEvent := AQuickSearch.edtSearch.OnChange;
  AQuickSearch.edtSearch.OnChange := nil;
  AQuickSearch.edtSearch.Text := Self.edtSearch.Text;
  AQuickSearch.edtSearch.SelStart := Self.edtSearch.SelStart;
  AQuickSearch.edtSearch.SelLength := Self.edtSearch.SelLength;
  AQuickSearch.edtSearch.OnChange := TempEvent;
  TempEvent := AQuickSearch.tglFilter.OnChange;
  AQuickSearch.tglFilter.OnChange := nil;
  AQuickSearch.tglFilter.Checked := Self.tglFilter.Checked;
  AQuickSearch.tglFilter.OnChange := TempEvent;
  AQuickSearch.FBarMode := Self.FBarMode;
  AQuickSearch.FPrefixFilter := Self.FPrefixFilter;
  AQuickSearch.UpdateModeLabel;
  AQuickSearch.Visible := Self.Visible;

  // Do not clone LimitedAutoHide but honor it instead, because it depends on the parent fileview
  if Self.Visible and not Self.edtSearch.Focused and Self.LimitedAutoHide and not AQuickSearch.LimitedAutoHide then
    AQuickSearch.FrameExit(nil); // do autohide if needed
end;

procedure TfrmQuickSearch.DoOnChangeSearch;
begin
  // in command and go-to modes nothing is searched while typing
  if FBarMode <> qbmSearch then
    Exit;

  if FUpdateCount > 0 then
    FNeedsChangeSearch := True
  else
  begin
    Options.LastSearchMode:=Self.Mode;
    case Self.Mode of
      qsSearch:
        if Assigned(Self.OnChangeSearch) then
          Self.OnChangeSearch(Self, GetSearchableText, Options);
      qsFilter:
        if Assigned(Self.OnChangeFilter) then
          Self.OnChangeFilter(Self, GetSearchableText, Options);
    end;
    FNeedsChangeSearch := False;
  end;
end;

procedure TfrmQuickSearch.Execute(SearchMode: TQuickSearchMode; const Params: array of String; Char: TUTF8Char = #0);
begin
  Self.Visible := True;

  if not edtSearch.Focused then
  begin
    edtSearch.SetFocus;
    edtSearch.SelectAll;
  end;

  if Char <> #0 then
    edtSearch.SelText := Char;

  Self.Active := True;

  ProcessParams(SearchMode, Params);
end;

procedure TfrmQuickSearch.Reset;
begin
  PopFilter;

  Options.LastSearchMode := qsNone;
  Options.Direction := qsdNone;
  Options.CancelSearchMode:=qscmNode;
end;

procedure TfrmQuickSearch.Finalize;
begin
  HideCommandList;
  Reset;
  Hide;
end;

{ TfrmQuickSearch.ProcessParams }
procedure TfrmQuickSearch.ProcessParams(const SearchMode: TQuickSearchMode; const Params: array of String);
var
  Param: String;
  Value: String;
  bWeGotMainParam: boolean = False;
  bLegacyBehavior: boolean = False;
  bDirectionRequested: boolean = False;
begin
  BeginUpdate;
  try
    Options.Direction:=qsdNone;

    for Param in Params do
    begin
      if (SearchMode=qsFilter) AND (GetParamValue(Param, PARAMETER_FILTER, Value)) then
      begin
        if (Value <> TOGGLE_VALUE) then
          tglFilter.Checked := GetBoolState(Value, tglFilter.Checked)
        else
          tglFilter.Checked := (not tglFilter.Checked) OR (Options.LastSearchMode<>qsFilter); //With "toggle", if mode was not previously, we activate filter mode.
        bWeGotMainParam := True;
      end
      else if (SearchMode=qsSearch) AND (GetParamValue(Param, PARAMETER_FILTER, Value)) then //Legacy
      begin
        tglFilter.Checked := GetBoolState(Value, tglFilter.Checked);
        bWeGotMainParam := True;
        bLegacyBehavior:= True;
      end
      else if (SearchMode=qsSearch) AND (GetParamValue(Param, PARAMETER_SEARCH, Value)) then
      begin
        if (Value <> CYCLE_VALUE) then
        begin
          Options.CancelSearchMode:=qscmNode;
          if (Value <> TOGGLE_VALUE) then
            tglFilter.Checked := not (GetBoolState(Value, tglFilter.Checked))
          else
            tglFilter.Checked := not((tglFilter.Checked) OR (Options.LastSearchMode<>qsSearch)); //With "toggle", if mode was not previously, we activate search mode.
        end
        else
        begin
          tglFilter.Checked:=FALSE;
          if Options.LastSearchMode<>qsSearch then
          begin
            Options.Direction:=qsdFirst; //With "cycle", if mode was not previously, we activate search mode AND do to first item
            Options.CancelSearchMode:=qscmAtLeastOneThenCancelIfNoFound;
          end
          else
          begin
            Options.Direction:=qsdNext;
            Options.CancelSearchMode:=qscmCancelIfNoFound;
          end;
        end;
        bWeGotMainParam := True;
      end
      else if (SearchMode=qsSearch) AND GetParamValue(Param, PARAMETER_DIRECTION, Value) then
      begin
        if Value = FIRST_VALUE then Options.Direction:=qsdFirst;
        if Value = LAST_VALUE then Options.Direction:=qsdLast;
        if Value = NEXT_VALUE then Options.Direction:=qsdNext;
        if Value = PREVIOUS_VALUE then Options.Direction:=qsdPrevious;
        bDirectionRequested := True;
      end
      else if GetParamValue(Param, PARAMETER_MATCH_BEGINNING, Value) then
      begin
        sbMatchBeginning.Down := GetBoolState(Value, sbMatchBeginning.Down);

        sbMatchBeginningClick(nil);
      end
      else if GetParamValue(Param, PARAMETER_MATCH_ENDING, Value) then
      begin
        sbMatchEnding.Down := GetBoolState(Value, sbMatchEnding.Down);

        sbMatchEndingClick(nil);
      end
      else if GetParamValue(Param, PARAMETER_CASE_SENSITIVE, Value) then
      begin
        sbCaseSensitive.Down := GetBoolState(Value, sbCaseSensitive.Down);

        sbCaseSensitiveClick(nil);
      end
      else if GetParamValue(Param, PARAMETER_FILES, Value) then
      begin
        sbFiles.Down := GetBoolState(Value, sbFiles.Down);

        sbFilesAndDirectoriesClick(nil);
      end
      else if GetParamValue(Param, PARAMETER_DIRECTORIES, Value) then
      begin
        sbDirectories.Down := GetBoolState(Value, sbDirectories.Down);

        sbFilesAndDirectoriesClick(nil);
      end
      else if Param = PARAMETER_FILES_DIRECTORIES then
      begin
        if sbFiles.Down and sbDirectories.Down then
          sbDirectories.Down := False
        else if sbFiles.Down then
        begin
          sbDirectories.Down := True;
          sbFiles.Down := False;
        end
        else if sbDirectories.Down then
          sbFiles.Down := True;

        sbFilesAndDirectoriesClick(nil);
      end
      else if GetParamValue(Param, PARAMETER_TEXT, Value) then
      begin
        edtSearch.Text := Value;
        edtSearch.SelectAll;
      end;
    end;

    // A bare direction request (default F3/Shift+F3 while the bar is open)
    // only jumps to another match; it must not switch between search and
    // filter mode nor close the bar.
    if bDirectionRequested and not bWeGotMainParam then
    begin
      if (Mode = qsSearch) and (Options.Direction <> qsdNone) then
        DoOnChangeSearch; // deferred until EndUpdate, Direction still set
      Exit;
    end;

    CheckFilesOrDirectoriesDown;

    //If search or filter was called with no parameter...
    case SearchMode of
      qsSearch: if not bWeGotMainParam then tglFilter.Checked:=False;
      qsFilter: if not bWeGotMainParam then tglFilter.Checked:=True;
    end;

    if not bLegacyBehavior then
    begin
      case SearchMode of
        qsSearch: if tglFilter.Checked then CancelFilter;
        qsFilter: if not tglFilter.Checked then CancelFilter;
      end;
    end;

  finally
    EndUpdate;
  end;
end;

function TfrmQuickSearch.CheckSearchOrFilter(var Key: Word): Boolean;
var
  ModifierKeys: TShiftState;
  SearchOrFilterModifiers: TShiftState;
  SearchMode: TQuickSearchMode;
  UTF8Char: TUTF8Char;
  KeyTypingModifier: TKeyTypingModifier;
begin
  Result := False;

  ModifierKeys := GetKeyShiftStateEx;

  for KeyTypingModifier in TKeyTypingModifier do
  begin
    if gKeyTyping[KeyTypingModifier] in [ktaQuickSearch, ktaQuickFilter] then
    begin
      SearchOrFilterModifiers := TKeyTypingModifierToShift[KeyTypingModifier];
      if ((SearchOrFilterModifiers <> []) and
         (ModifierKeys * KeyModifiersShortcutNoText = SearchOrFilterModifiers))
{$IFDEF MSWINDOWS}
      // Entering international characters with Ctrl+Alt on Windows.
      or (HasKeyboardAltGrKey and (SearchOrFilterModifiers = []) and
          (ModifierKeys * KeyModifiersShortcutNoText = [ssCtrl, ssAlt]))
{$ENDIF}
      then
      begin
        if (Key <> VK_SPACE) or (edtSearch.Text <> '') then
        begin
          UTF8Char := VirtualKeyToUTF8Char(Key, ModifierKeys - SearchOrFilterModifiers);
          Result := (UTF8Char <> '') and
                    (not ((Length(UTF8Char) = 1) and (UTF8Char[1] in [#0..#31])));

          if Result then
          begin
            Key := 0;
            case gKeyTyping[KeyTypingModifier] of
              ktaQuickSearch:
                SearchMode := qsSearch;
              ktaQuickFilter:
                SearchMode := qsFilter;
            end;
            Self.Execute(SearchMode, [], UTF8Char);
          end;
        end;

        Exit;
      end;
    end;
  end;
end;

function TfrmQuickSearch.CheckSearchOrFilter(var UTF8Key: TUTF8Char): Boolean;
var
  ModifierKeys: TShiftState;
  SearchMode: TQuickSearchMode;
  KeyTypingModifier: TKeyTypingModifier;
begin
  Result := False;

  // Check for certain Ascii keys.
  if (Length(UTF8Key) = 1) and (UTF8Key[1] in [#0..#32,'+','-']) then
    Exit;

  // '*' starts the bar in filter mode, but only from the main keyboard:
  // Num* is the invert-selection hotkey and must not leak into typing.
  if (UTF8Key = '*') and (GetKeyState(VK_MULTIPLY) < 0) then
    Exit;

  ModifierKeys := GetKeyShiftStateEx;
  for KeyTypingModifier in [ktmNone, ktmAlt] do
  if gKeyTyping[KeyTypingModifier] in [ktaQuickSearch, ktaQuickFilter] then
  begin
    {$IFDEF DARWIN}
    if ssAltGr in ModifierKeys then
      continue;
    {$ENDIF}
    if ModifierKeys * KeyModifiersShortcutNoText = TKeyTypingModifierToShift[KeyTypingModifier] then
      begin
        // Make upper case if either caps-lock is toggled or shift pressed.
        if (ssCaps in ModifierKeys) xor (ssShift in ModifierKeys) then
          UTF8Key := UTF8UpperCase(UTF8Key)
        else
          UTF8Key := UTF8LowerCase(UTF8Key);

        case gKeyTyping[ktmNone] of
          ktaQuickSearch:
            SearchMode := qsSearch;
          ktaQuickFilter:
            SearchMode := qsFilter;
        end;

        Self.Execute(SearchMode, [], UTF8Key);
        UTF8Key := '';

        Result := True;

        Exit;
      end;
  end;
end;

procedure TfrmQuickSearch.LoadControlStates;
begin
  sbDirectories.Down := (Options.Items = qsiDirectories) or (Options.Items = qsiFilesAndDirectories);
  sbFiles.Down := (Options.Items = qsiFiles) or (Options.Items = qsiFilesAndDirectories);
  sbCaseSensitive.Down := Options.SearchCase = qscSensitive;
  sbMatchBeginning.Down := qsmBeginning in Options.Match;
  sbMatchEnding.Down := qsmEnding in Options.Match;
  sbDiacritics.Down := Options.Diacritics;
end;

procedure TfrmQuickSearch.PushFilter;
begin
  FilterText := edtSearch.Text;
  FilterOptions := Options;
end;

procedure TfrmQuickSearch.PopFilter;
begin
  edtSearch.Text := FilterText;

  // there was no filter saved, do not continue loading
  if FilterText = EmptyStr then
    Exit;

  Options := FilterOptions;
  LoadControlStates;

  FilterText := EmptyStr;

  tglFilter.Checked := True;
end;

procedure TfrmQuickSearch.ClearFilter;
begin
  FilterText := EmptyStr;
  FilterOptions := Options;

  if Assigned(Self.OnChangeFilter) then
    Self.OnChangeFilter(Self, EmptyStr, FilterOptions);
end;

procedure TfrmQuickSearch.CancelFilter;
begin
  Finalize;
  {$IFDEF LCLGTK2}
  // On GTK2 OnExit for frame is not called when it is hidden,
  // but only when a control from outside of frame gains focus.
  FrameExit(nil);
  {$ENDIF}
  DoHide;
end;

procedure TfrmQuickSearch.SetFocus(Data: PtrInt);
begin
  if edtSearch.CanFocus then edtSearch.SetFocus;
end;

procedure TfrmQuickSearch.RestoreFocus(Data: PtrInt);
begin
  if Assigned(Screen.ActiveControl) then
  begin
    // The file panel has lost focus
    if Screen.ActiveControl is TCustomForm then
    begin
      if Parent.CanSetFocus then Parent.SetFocus;
    end;
  end;
end;

procedure TfrmQuickSearch.CheckFilesOrDirectoriesDown;
begin
  if not (sbFiles.Down or sbDirectories.Down) then
  begin
    // unchecking both should not be possible, so recheck last unchecked
    case Options.Items of
      qsiFiles:
        sbFiles.Down := True;
      qsiDirectories:
        sbDirectories.Down := True;
    end;
  end;
end;

procedure TfrmQuickSearch.edtSearchChange(Sender: TObject);
begin
  UpdateBarMode;

  case FBarMode of
    qbmCommand:
      UpdateCommandList;
    qbmGoTo:
      UpdateAliasList; // navigation happens on Enter only
    else
    begin
      Options.Direction := qsdNone;
      DoOnChangeSearch;
    end;
  end;
end;

procedure TfrmQuickSearch.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TfrmQuickSearch.btnCancelClick(Sender: TObject);
begin
  CancelFilter;
end;

procedure TfrmQuickSearch.edtSearchKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if CheckSearchOrFilter(Key) then
    Exit;

  case FBarMode of
    qbmCommand:
      case Key of
        VK_DOWN:
        begin
          Key := 0;
          MoveCommandSelection(1);
          Exit;
        end;
        VK_UP:
        begin
          Key := 0;
          MoveCommandSelection(-1);
          Exit;
        end;
        VK_RETURN, VK_SELECT:
        begin
          Key := 0;
          ExecuteSelectedCommand;
          Exit;
        end;
      end;
    qbmGoTo:
      case Key of
        VK_RETURN, VK_SELECT:
        begin
          Key := 0;
          DoGoToPath;
          Exit;
        end;
        VK_DOWN:
        begin
          Key := 0;
          MoveCommandSelection(1);
          Exit;
        end;
        VK_UP:
        begin
          Key := 0;
          MoveCommandSelection(-1);
          Exit;
        end;
      end;
    qbmSearch: ; // handled below
  end;

  case Key of
    VK_DOWN:
    begin
      Key := 0;

      if Assigned(Self.OnChangeSearch) then
      begin
        Options.Direction:=qsdNext;
        Self.OnChangeSearch(Self, GetSearchableText, Options, ssShift in Shift);
      end;
    end;

    VK_UP:
    begin
      Key := 0;

      if Assigned(Self.OnChangeSearch) then
      begin
        Options.Direction:=qsdPrevious;
        Self.OnChangeSearch(Self, GetSearchableText, Options, ssShift in Shift);
      end;
    end;

    // Request to have CTRL pressed at the same time.
    // VK_HOME alone reserved to get to start position of edtSearch.
    VK_HOME:
    begin
      if ssCtrl in Shift then
      begin
        Key := 0;

        if Assigned(Self.OnChangeSearch) then
        begin
          Options.Direction := qsdFirst;
          Self.OnChangeSearch(Self, GetSearchableText, Options, ssShift in Shift);
        end;
      end;
    end;

    // Request to have CTRL pressed at the same time.
    // VK_END alone reserved to get to end position of edtSearch.
    VK_END:
    begin
      if ssCtrl in Shift then
      begin
        Key := 0;

        if Assigned(Self.OnChangeSearch) then
        begin
          Options.Direction := qsdLast;
          Self.OnChangeSearch(Self, GetSearchableText, Options, ssShift in Shift);
        end;
      end;
    end;

    VK_INSERT:
    begin
      if Shift = [] then // no modifiers pressed, to not capture Ctrl+Insert and Shift+Insert
      begin
        Key := 0;

        if Assigned(Self.OnChangeSearch) then
        begin
          Options.Direction := qsdNext;
          Self.OnChangeSearch(Self, GetSearchableText, Options, True);
        end;
      end;
    end;

    VK_RETURN, VK_SELECT:
    begin
      Key := 0;

      if Assigned(Self.OnExecute) then
        Self.OnExecute(Self);

      CancelFilter;
    end;

    VK_TAB:
    begin
      Key := 0;

      FIntendedLeave := True;
      DoHide;
    end;

    VK_ESCAPE:
    begin
      Key := 0;

      CancelFilter;
    end;
  end;
end;

procedure TfrmQuickSearch.EndUpdate;
begin
  Dec(FUpdateCount);
  if FUpdateCount = 0 then
  begin
    if FNeedsChangeSearch then
      DoOnChangeSearch;
  end;
end;

procedure TfrmQuickSearch.DoHide;
begin
  if Assigned(Self.OnHide) then
    Self.OnHide(Self);
end;

procedure TfrmQuickSearch.FrameExit(Sender: TObject);
var
  DontHide: Boolean;
begin
  // clicking the command palette must not close the bar
  if Assigned(lsCommands) and
     (lsCommands.Focused or (Screen.ActiveControl = lsCommands)) then
  begin
    Application.QueueAsyncCall(@SetFocus, 0);
    Exit;
  end;

{$IF DEFINED(LCLQT) or DEFINED(LCLQT5) or DEFINED(LCLQT6)}
  // Workaround: QuickSearch frame lose focus on SpeedButton click
  if Screen.ActiveControl is TFileView then
    edtSearch.SetFocus
  else
{$ENDIF}
  if not Finalizing then
  begin
    Finalizing := True;

    Self.Active := False;

    if FIntendedLeave then
    begin
      FIntendedLeave := False;
      DontHide := False;
    end
    else
      DontHide := LimitedAutoHide;

    if (Mode = qsFilter) and (edtSearch.Text <> EmptyStr) then
      Self.Visible := DontHide or not gQuickFilterAutoHide
    else begin
      if DontHide then Reset else Finalize;
    end;
    Application.QueueAsyncCall(@RestoreFocus, 0);

    Finalizing := False;
  end;
end;

procedure TfrmQuickSearch.sbDiacriticsClick(Sender: TObject);
begin
  Options.Diacritics := sbDiacritics.Down;

  if gQuickFilterSaveSessionModifications then gQuickSearchOptions.Diacritics := Options.Diacritics;

  Options.Direction := qsdNone;

  DoOnChangeSearch;
end;

procedure TfrmQuickSearch.sbCaseSensitiveClick(Sender: TObject);
begin
  if sbCaseSensitive.Down then
    Options.SearchCase := qscSensitive
  else
    Options.SearchCase := qscInsensitive;

  if gQuickFilterSaveSessionModifications then gQuickSearchOptions.SearchCase := Options.SearchCase;

  Options.Direction := qsdNone;

  DoOnChangeSearch;
end;

procedure TfrmQuickSearch.sbFilesAndDirectoriesClick(Sender: TObject);
begin
  if sbFiles.Down and sbDirectories.Down then
    Options.Items := qsiFilesAndDirectories
  else if sbFiles.Down then
    Options.Items := qsiFiles
  else if sbDirectories.Down then
    Options.Items := qsiDirectories
  else if FUpdateCount = 0 then
  begin
    CheckFilesOrDirectoriesDown;
    Exit;
  end;

  if gQuickFilterSaveSessionModifications then gQuickSearchOptions.Items := Options.Items;

  Options.Direction := qsdNone;

  DoOnChangeSearch;
end;

procedure TfrmQuickSearch.sbMatchBeginningClick(Sender: TObject);
begin
  if sbMatchBeginning.Down then
    Include(Options.Match, qsmBeginning)
  else
    Exclude(Options.Match, qsmBeginning);

  if gQuickFilterSaveSessionModifications then gQuickSearchOptions.Match := Options.Match;

  Options.Direction := qsdNone;

  DoOnChangeSearch;
end;

procedure TfrmQuickSearch.sbMatchEndingClick(Sender: TObject);
begin
  if sbMatchEnding.Down then
    Include(Options.Match, qsmEnding)
  else
    Exclude(Options.Match, qsmEnding);

  if gQuickFilterSaveSessionModifications then gQuickSearchOptions.Match := Options.Match;

  Options.Direction := qsdNone;

  DoOnChangeSearch;
end;

procedure TfrmQuickSearch.tglFilterChange(Sender: TObject);
begin
  Options.LastSearchMode := qsNone;
  if tglFilter.Checked then
    Mode := qsFilter
  else
    Mode := qsSearch;

  // if a filter was set in background and a search is opened, the filter
  // will get pushed staying active. Otherwise the filter will be converted
  // in a search
  if not Active and (Mode = qsSearch) then
    PushFilter
  else if Active then
    ClearFilter;

  Options.Direction := qsdNone;

  DoOnChangeSearch;
end;

procedure TfrmQuickSearch.btnMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  Application.QueueAsyncCall(@SetFocus, 0);
end;

procedure TfrmQuickSearch.btnCancelMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Self.Visible then Application.QueueAsyncCall(@SetFocus, 0);
end;

procedure TfrmQuickSearch.UpdateBarMode;
var
  S: String;
  NewMode: TQuickBarMode;
begin
  S := edtSearch.Text;

  if (S <> EmptyStr) and (S[1] = CMD_MODE_PREFIX) then
    NewMode := qbmCommand
  else if IsGoToText(S) then
    NewMode := qbmGoTo
  else
    NewMode := qbmSearch;

  if NewMode <> FBarMode then
  begin
    FBarMode := NewMode;
    if FBarMode <> qbmCommand then
      HideCommandList;
    UpdateModeLabel;
  end;

  // a leading '*' switches into (and back out of) filter mode
  if FBarMode = qbmSearch then
  begin
    if (S <> EmptyStr) and (S[1] = FILTER_MODE_PREFIX) then
    begin
      if not tglFilter.Checked then
      begin
        FPrefixFilter := True;
        tglFilter.Checked := True; // triggers tglFilterChange
      end;
    end
    else if FPrefixFilter then
    begin
      FPrefixFilter := False;
      if tglFilter.Checked then
        tglFilter.Checked := False;
    end;
  end;
end;

procedure TfrmQuickSearch.UpdateModeLabel;
begin
  case FBarMode of
    qbmCommand:
      lblMode.Caption := rsQuickSearchModeCommand;
    qbmGoTo:
      lblMode.Caption := rsQuickSearchModeGoTo;
    else
      lblMode.Caption := EmptyStr;
  end;
end;

function TfrmQuickSearch.GetSearchableText: String;
begin
  Result := edtSearch.Text;
  if FPrefixFilter and (Result <> EmptyStr) and (Result[1] = FILTER_MODE_PREFIX) then
    Delete(Result, 1, 1);
end;

procedure TfrmQuickSearch.EnsureCommandCache;
var
  I: Integer;
  List: TStringList;
begin
  if Assigned(FCommandCache) then
    Exit;

  FCommandCache := TStringList.Create;
  FCommandCaptions := TStringList.Create;

  List := TStringList.Create;
  try
    frmMain.Commands.Commands.GetCommandsList(List);
    List.Sort;
    for I := 0 to List.Count - 1 do
    begin
      FCommandCache.Add(List[I]);
      FCommandCaptions.Add(frmMain.Commands.Commands.GetCommandCaption(List[I], cctShort));
    end;
  finally
    List.Free;
  end;
end;

procedure TfrmQuickSearch.UpdateCommandList;
var
  I, P: Integer;
  Filter, CmdName: String;

  function MakeItem(Index: Integer): String;
  begin
    Result := FCommandCache[Index];
    if FCommandCaptions[Index] <> EmptyStr then
      Result := Result + '   -   ' + FCommandCaptions[Index];
  end;

begin
  EnsureCommandCache;

  Filter := UTF8LowerCase(Trim(Copy(edtSearch.Text, 2, MaxInt)));

  lsCommands.Items.BeginUpdate;
  try
    lsCommands.Items.Clear;
    FDropdownValues.Clear;
    // commands whose name begins with the typed text come first...
    for I := 0 to FCommandCache.Count - 1 do
    begin
      CmdName := UTF8LowerCase(FCommandCache[I]);
      P := Pos(Filter, CmdName);
      if (Filter = EmptyStr) or (P = 1) or (P = 4) then // 4 = right after 'cm_'
      begin
        lsCommands.Items.Add(MakeItem(I));
        FDropdownValues.Add(FCommandCache[I]);
      end;
    end;
    // ...then matches elsewhere in the name or in the caption
    if Filter <> EmptyStr then
      for I := 0 to FCommandCache.Count - 1 do
      begin
        CmdName := UTF8LowerCase(FCommandCache[I]);
        P := Pos(Filter, CmdName);
        if ((P > 1) and (P <> 4)) or
           ((P = 0) and (Pos(Filter, UTF8LowerCase(FCommandCaptions[I])) > 0)) then
        begin
          lsCommands.Items.Add(MakeItem(I));
          FDropdownValues.Add(FCommandCache[I]);
        end;
      end;
  finally
    lsCommands.Items.EndUpdate;
  end;

  ShowDropdown;
end;

procedure TfrmQuickSearch.UpdateAliasList;
var
  I: Integer;
  S, Typed, AName: String;

  procedure AddAlias(Index: Integer);
  begin
    lsCommands.Items.Add(PATH_MODE_PREFIX + gPathAliases.Names[Index] +
                         '   -   ' + gPathAliases.ValueFromIndex[Index]);
    FDropdownValues.Add(gPathAliases.ValueFromIndex[Index]);
  end;

begin
  S := edtSearch.Text;

  // no completion while an "=" alias definition is being typed
  if (S = EmptyStr) or ((S[1] in PATH_SEPARATORS) and (Pos('=', S) > 0)) then
  begin
    HideCommandList;
    Exit;
  end;

  // aliases apply to "/..." (and "\..." on Windows) only while typing the
  // first segment; deeper paths and "~"/drive forms complete real subdirectories
  if (not (S[1] in PATH_SEPARATORS)) or (FindPathSeparator(S, 2) > 0) then
  begin
    UpdateDirectoryList;
    Exit;
  end;

  Typed := UTF8LowerCase(Copy(S, 2, MaxInt));

  lsCommands.Items.BeginUpdate;
  try
    lsCommands.Items.Clear;
    FDropdownValues.Clear;
    // aliases whose name begins with the typed text come first...
    for I := 0 to gPathAliases.Count - 1 do
    begin
      AName := UTF8LowerCase(gPathAliases.Names[I]);
      if (Typed = EmptyStr) or (Pos(Typed, AName) = 1) then
        AddAlias(I);
    end;
    // ...then matches elsewhere in the name
    if Typed <> EmptyStr then
      for I := 0 to gPathAliases.Count - 1 do
      begin
        AName := UTF8LowerCase(gPathAliases.Names[I]);
        if Pos(Typed, AName) > 1 then
          AddAlias(I);
      end;
{$IFDEF MSWINDOWS}
    // built-in "This PC" alias (unless the user defined their own)
    if (Win32MajorVersion > 5) and (gPathAliases.IndexOfName('thispc') < 0) and
       ((Typed = EmptyStr) or (Pos(Typed, 'thispc') = 1)) then
    begin
      lsCommands.Items.Add(PATH_MODE_PREFIX + 'thispc' +
                           '   -   ' + TShellFileSource.RootName);
      FDropdownValues.Add(PathDelim + PathDelim + PathDelim +
                          TShellFileSource.RootName + PathDelim);
    end;
{$ENDIF}
  finally
    lsCommands.Items.EndUpdate;
  end;

  ShowDropdown;
end;

procedure TfrmQuickSearch.UpdateDirectoryList;
var
  S, BaseDir, Typed, AName: String;
  I, P: Integer;
  sr: TSearchRecEx;
  Names: TStringList;
{$IFDEF MSWINDOWS}
  Drive: String;
{$ENDIF}

  procedure AddDirectory(Index: Integer);
  var
    Suggestion: String;
  begin
    // an alias value and the typed text may use different slash styles;
    // show and store one native form (no-op on Unix)
    Suggestion := NormalizePathDelimiters(BaseDir + Names[Index]);
    lsCommands.Items.Add(Suggestion);
    FDropdownValues.Add(Suggestion);
  end;

begin
  S := edtSearch.Text;

{$IFDEF MSWINDOWS}
  // "C:" - complete from the root of that drive
  if (Length(S) = 2) and (S[2] = ':') then
    S := S + PathDelim;
{$ENDIF}

  // split at the last path separator: base directory + partial name typed
  P := 0;
  for I := Length(S) downto 1 do
    if S[I] in PATH_SEPARATORS then
    begin
      P := I;
      Break;
    end;

  if P = 0 then
  begin
    HideCommandList;
    Exit;
  end;

  BaseDir := ResolveGoToPath(Copy(S, 1, P));
  Typed := UTF8LowerCase(Copy(S, P + 1, MaxInt));

{$IFDEF MSWINDOWS}
  // "\path" (or "/path" with no alias) - path on the active panel's drive,
  // same as quickSearchGoToPath will do; leave UNC paths ("\\server") alone
  if (BaseDir[1] in PATH_SEPARATORS) and
     not ((Length(BaseDir) > 1) and (BaseDir[2] in PATH_SEPARATORS)) then
  begin
    Drive := ExtractFileDrive(frmMain.ActiveFrame.CurrentPath);
    if Drive = EmptyStr then Drive := 'C:';
    BaseDir := Drive + BaseDir;
  end;
{$ENDIF}

  if not mbDirectoryExists(BaseDir) then
  begin
    HideCommandList;
    Exit;
  end;

  Names := TStringList.Create;
  try
    try
      if FindFirstEx(BaseDir + '*', 0, sr) = 0 then
        repeat
          if (sr.Name <> '.') and (sr.Name <> '..') and FPS_ISDIR(sr.Attr) then
            Names.Add(sr.Name);
        until FindNextEx(sr) <> 0;
    finally
      FindCloseEx(sr);
    end;

    Names.Sort;

    lsCommands.Items.BeginUpdate;
    try
      lsCommands.Items.Clear;
      FDropdownValues.Clear;
      // directories whose name begins with the typed text come first...
      for I := 0 to Names.Count - 1 do
      begin
        AName := UTF8LowerCase(Names[I]);
        if (Typed = EmptyStr) or (Pos(Typed, AName) = 1) then
          AddDirectory(I);
      end;
      // ...then matches elsewhere in the name
      if Typed <> EmptyStr then
        for I := 0 to Names.Count - 1 do
        begin
          AName := UTF8LowerCase(Names[I]);
          if Pos(Typed, AName) > 1 then
            AddDirectory(I);
        end;
    finally
      lsCommands.Items.EndUpdate;
    end;
  finally
    Names.Free;
  end;

  ShowDropdown;
end;

procedure TfrmQuickSearch.ShowDropdown;
var
  AItemHeight, ListHeight: Integer;
begin
  FDropdownPicked := False;

  if lsCommands.Items.Count = 0 then
    HideCommandList
  else
  begin
    AItemHeight := lsCommands.ItemHeight;
    if AItemHeight <= 0 then
      AItemHeight := lsCommands.Canvas.TextHeight('Wg') + 2;
    ListHeight := Min(MAX_VISIBLE_COMMANDS, lsCommands.Items.Count) * AItemHeight + 8;
    if ListHeight > Top then
      ListHeight := Max(AItemHeight, Top);
    lsCommands.SetBounds(Left, Top - ListHeight, Width, ListHeight);
    lsCommands.Visible := True;
    lsCommands.BringToFront;
    lsCommands.ItemIndex := 0;
  end;
end;

procedure TfrmQuickSearch.HideCommandList;
begin
  FDropdownPicked := False;
  if Assigned(lsCommands) then
    lsCommands.Visible := False;
end;

procedure TfrmQuickSearch.MoveCommandSelection(ADelta: Integer);
var
  NewIndex: Integer;
begin
  if (not lsCommands.Visible) or (lsCommands.Items.Count = 0) then
    Exit;

  FDropdownPicked := True;
  NewIndex := lsCommands.ItemIndex + ADelta;
  if NewIndex < 0 then
    NewIndex := lsCommands.Items.Count - 1
  else if NewIndex >= lsCommands.Items.Count then
    NewIndex := 0;
  lsCommands.ItemIndex := NewIndex;
end;

procedure TfrmQuickSearch.ExecuteSelectedCommand;
var
  CmdName: String;
begin
  if lsCommands.Visible and (lsCommands.ItemIndex >= 0) and
     (lsCommands.ItemIndex < FDropdownValues.Count) then
    CmdName := FDropdownValues[lsCommands.ItemIndex]
  else
    CmdName := Trim(Copy(edtSearch.Text, 2, MaxInt));

  CancelFilter;

  if CmdName <> EmptyStr then
  begin
    // execute after the file panel got focus back
    FPendingCommand := CmdName;
    Application.QueueAsyncCall(@ExecutePendingCommand, 0);
  end;
end;

procedure TfrmQuickSearch.ExecutePendingCommand(Data: PtrInt);
begin
  if FPendingCommand <> EmptyStr then
    frmMain.Commands.Commands.ExecuteCommand(FPendingCommand, []);
  FPendingCommand := EmptyStr;
end;

procedure TfrmQuickSearch.lsCommandsDblClick(Sender: TObject);
begin
  case FBarMode of
    qbmCommand: ExecuteSelectedCommand;
    qbmGoTo:
      begin
        FDropdownPicked := True; // an explicit click always wins
        DoGoToPath;
      end;
  end;
end;

procedure TfrmQuickSearch.DoGoToPath;
var
  S, AName, AValue, Path: String;
  P: Integer;
begin
  S := Trim(edtSearch.Text);

  // "/name=path" defines an alias, "/name=" points it at the active panel's
  // current directory, "/=" names the alias after the current directory itself,
  // "/name=-" removes it
  if (Length(S) > 1) and (S[1] = PATH_MODE_PREFIX) then
  begin
    P := Pos('=', S);
    if P >= 2 then
    begin
      AName := Copy(S, 2, P - 2);
      AValue := Trim(Copy(S, P + 1, MaxInt));
      if AValue = '-' then
      begin
        P := gPathAliases.IndexOfName(AName);
        if P >= 0 then
          gPathAliases.Delete(P);
      end
      else
      begin
        if AValue = EmptyStr then
          AValue := frmMain.ActiveFrame.CurrentPath;
        AValue := ExcludeTrailingPathDelimiter(NormalizePathDelimiters(AValue));
        if AName = EmptyStr then
          AName := ExtractFileName(AValue);
        if (AName <> EmptyStr) and (AValue <> EmptyStr) then
          gPathAliases.Values[AName] := AValue;
      end;
      CancelFilter;
      Exit;
    end;
  end;

  Path := ResolveGoToPath(S);

  // Take the highlighted dropdown suggestion instead, unless the typed text
  // already resolves to an existing directory by itself. An entry explicitly
  // picked with the arrow keys or the mouse always wins.
  if lsCommands.Visible and (lsCommands.ItemIndex >= 0) and
     (lsCommands.ItemIndex < FDropdownValues.Count) then
  begin
    if FDropdownPicked or not mbDirectoryExists(Path) then
      Path := FDropdownValues[lsCommands.ItemIndex];
  end;

  CancelFilter;

  if (Path <> EmptyStr) and Assigned(OnGoToPath) then
    OnGoToPath(Self, Path);
end;

function TfrmQuickSearch.IsGoToText(const S: String): Boolean;
begin
  if S = EmptyStr then
    Exit(False);

  Result := (S[1] = PATH_MODE_PREFIX) or (S[1] = PATH_MODE_HOME)
{$IFDEF MSWINDOWS}
    // "\path" - path on the current drive
    or (S[1] = '\')
    // "C:", "C:\path" - path with a drive letter
    or ((Length(S) >= 2) and (S[2] = ':') and (UpCase(S[1]) in ['A'..'Z']))
{$ENDIF}
    ;
end;

function TfrmQuickSearch.FindPathSeparator(const S: String; FromPos: Integer): Integer;
begin
  for Result := FromPos to Length(S) do
    if S[Result] in PATH_SEPARATORS then
      Exit;
  Result := 0;
end;

function TfrmQuickSearch.ResolveGoToPath(const S: String): String;
var
  P: Integer;
  First, Rest, Alias: String;
begin
  Result := S;
  if S = EmptyStr then
    Exit;

  // expand "~" to the home directory
  if S[1] = PATH_MODE_HOME then
  begin
    if Length(S) = 1 then
      Result := GetHomeDir
    else if S[2] in ['/', '\'] then
      Result := IncludeTrailingPathDelimiter(GetHomeDir) + Copy(S, 3, MaxInt);
    Exit;
  end;

{$IFDEF MSWINDOWS}
  // "C:", "C:\path" - already a full path
  if (Length(S) >= 2) and (S[2] = ':') then
    Exit;
{$ENDIF}

  if not (S[1] in PATH_SEPARATORS) then
    Exit;

  // "/name[/rest]" - look up "name" in the path aliases;
  // if nothing matches the text is left as typed (a literal path)
  P := FindPathSeparator(S, 2);
  if P = 0 then
  begin
    First := Copy(S, 2, MaxInt);
    Rest := EmptyStr;
  end
  else
  begin
    First := Copy(S, 2, P - 2);
    Rest := Copy(S, P, MaxInt);
  end;

  Alias := gPathAliases.Values[First];

{$IFDEF MSWINDOWS}
  // "/thispc" - built-in alias for the shell "This PC" folder;
  // a user-defined alias of the same name wins
  if (Alias = EmptyStr) and (Win32MajorVersion > 5) and SameText(First, 'thispc') then
  begin
    Result := PathDelim + PathDelim + PathDelim + TShellFileSource.RootName + PathDelim;
    if Rest <> EmptyStr then
      Result := Result + NormalizePathDelimiters(Copy(Rest, 2, MaxInt));
    Exit;
  end;
{$ENDIF}

  if Alias <> EmptyStr then
    Result := Alias + Rest;
end;

end.

