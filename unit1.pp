unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, process, FileUtil, Forms, Controls, Graphics, Dialogs,
  ComCtrls, StdCtrls, Spin, StrUtils, Syncobjs;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Edit1: TEdit;
    ListView1: TListView;
    OpenDialog1: TOpenDialog;
    ProgressBar1: TProgressBar;
    SpinEdit1: TSpinEdit;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure SpinEdit1Change(Sender: TObject);
  private
    { private declarations }
    function AddFile(const FilePath: string): boolean;
    procedure EnableControls(Enable: boolean);
    procedure CleanProgressAndResult;
    function FileAlreadyInList(const FilePath: string): boolean;
  public
    { public declarations }
  end;

  { TUPXThread }

  TUPXThread = class(TThread)
  private
    { Private declarations }
    FIndex: integer;
    FDoneCount: PInteger;
    FThreadCount: PInteger;
    FForm: TForm1;
    FUPXCmd: string;
    FUPXArgs: TStrings;
    FResultMsg: string;
    procedure UpdateStatus;
  public
    property ResultMsg: string read FResultMsg;
    constructor Create(const AIndex: integer; ADoneCount, AThreadCount: PInteger;
      AForm: TForm1; const AUPXCmd: string; const AUPXArgs: TStrings);
    destructor Destroy; override;
    procedure Execute; override;
  end;

  { TUPXThreadRunner }

  TUPXThreadRunner = class(TThread)
  private
    FForm: TForm1;
    FUPXFile: string;
  public
    constructor Create(AForm: TForm1; const AUPXFile: string);
    procedure Execute; override;
  end;

var
  Form1: TForm1;
  UPXThreadCount: integer = 1;

implementation

{$R *.lfm}

threadvar
  ListItemCS: TCriticalSection;

function FormatFileSize(FilePath: string): string;
var
  TheFileSize: int64;
  StrFileSize: string;
begin
  TheFileSize := FileSize(FilePath);
  if TheFileSize = -1 then
  begin
    Result := '';
    Exit;
  end;
  StrFileSize := IntToStr(TheFileSize);
  case Length(StrFileSize) of
    1..3: Result := StrFileSize + ' B';
    4..6: Result := IntToStr(TheFileSize shr 10) + ' KB';
    7..9: Result := IntToStr(TheFileSize shr 20) + ' MB';
    else
      Result := IntToStr(TheFileSize shr 30) + ' GB';
  end;
end;

procedure Error(AMsg: string);
begin
  MessageDlg('ERROR!', AMsg, mtError, [mbOK], 0);
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  UPXFile: string;
begin
  UPXFile := Edit1.Text;
  CleanProgressAndResult;
  EnableControls(False);
  TUPXThreadRunner.Create(Self, UPXFile);
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  NumOfFiles: byte;
begin
  if OpenDialog1.Execute then
    for NumOfFiles := 0 to OpenDialog1.Files.Count - 1 do
      AddFile(OpenDialog1.Files.Strings[NumOfFiles]);
end;

procedure TForm1.SpinEdit1Change(Sender: TObject);
begin
  UPXThreadCount := SpinEdit1.Value;
end;

procedure TForm1.EnableControls(Enable: boolean);
var
  i: integer;
begin
  for i := 0 to ControlCount - 1 do
    Controls[i].Enabled := Enable;
end;

function TForm1.AddFile(const FilePath: string): boolean;

  function Supported(const Ext: string): boolean;
  const
    {$ifdef Windows}
    SupportedFmtCount = 10;
    {$endif}
    {$ifdef Unix}
    SupportedFmtCount = 11;
    {$endif}
  var
    SupportedFmt: array [0..SupportedFmtCount - 1] of
    string = ('.exe', '.dll', '.com', '.sys', '.ocx', '.scr',
      '.dpl', '.bpl', '.acm', '.ax'
      {$ifdef Unix}
      , ''
      {$endif}
      );
    i: byte;
  begin
    Result := False;
    i := Low(SupportedFmt);
    repeat
      if LowerCase(Ext) = SupportedFmt[i] then
        Result := True;
      Inc(i);
    until Result or (i > High(SupportedFmt));
  end;

  function IsUPXedAlready: boolean;
  begin
    with TStringList.Create do
    try
      LoadFromFile(FilePath);
      Result := Pos('UPX!', Text) > 0;
    finally
      Free;
    end;
  end;

var
  NewItem: TListItem;
  NewFileSize: string;
  Ext: string;
begin
  Result := True;
  Ext := ExtractFileExt(FilePath);
  if not Supported(Ext) then
  begin
    Result := False;
    Exit;
  end;
  NewFileSize := FormatFileSize(FilePath);
  if NewFileSize = '' then
    Exit;
  if not FileAlreadyInList(FilePath) then
  begin
    NewItem := ListView1.Items.Add;
    with NewItem do
    begin
      Caption := ExtractFileName(FilePath);
      SubItems.Add(FilePath);
      SubItems.Add(NewFileSize);
      SubItems.Add('');
      SubItems.Add('');
      Checked := not IsUPXedAlready;
    end;
  end
  else
    Error('The file "' + FilePath + '" is already in the list!');
end;

procedure TForm1.CleanProgressAndResult;
var
  i: integer;
begin
  for i := 0 to ListView1.Items.Count - 1 do
    with ListView1.Items[i] do
    begin
      SubItems[3] := '';
      SubItems[2] := '';
    end;
  ProgressBar1.Position := 0;
end;

function TForm1.FileAlreadyInList(const FilePath: string): boolean;
var
  i: integer;
begin
  Result := False;
  if ListView1.Items.Count = 0 then
    Exit;
  i := 0;
  repeat
    if ListView1.Items.Item[i].SubItems.Strings[0] = FilePath then
      Result := True;
    Inc(i);
  until Result or (i = ListView1.Items.Count);
end;

{ TUPXThread }

procedure TUPXThread.Execute;
var
  TempPos: longword;
begin
  with TProcess.Create(nil) do
  try
    try
      Options := [poWaitOnExit, poNoConsole, poUsePipes];
      {$if FPC_FULLVERSION < 20600}
      FUPXArgs.Delimiter := ' ';
      CommandLine := FUPXCmd + FUPXArgs.DelimitedText + ' "' +
        FForm.ListView1.Items[FIndex].SubItems[0] + '"';
      {$else}
        Executable := FUPXCmd;
        Parameters.AddStrings(FUPXArgs);
        Parameters.Add(FForm.ListView1.Items[FIndex].SubItems[0]);
      {$endif}
      FUPXArgs.Free;
      Execute;
      if ExitStatus <> 0 then
      begin
        with TStringList.Create do
        try
          LoadFromStream(StdErr);
          FResultMsg := Text;
        finally
          Free;
        end;
        TempPos := RPosEx(':', FResultMsg, RPos(':', FResultMsg) - 1);
        if FResultMsg[TempPos + 1] <> DirectorySeparator then
          FResultMsg := Copy(FResultMsg, TempPos + 1,
            Length(FResultMsg) - TempPos)
        else
          FResultMsg := Copy(FResultMsg, TempPos - 1,
            Length(FResultMsg) - TempPos);
      end
      else
        FResultMsg := 'OK';
    except
      on e: Exception do
        FResultMsg := e.Message;
    end;
    Synchronize(@UpdateStatus);
  finally
    Free;
  end;
end;

procedure TUPXThread.UpdateStatus;
begin
  ListItemCS.Acquire;
  try
    with FForm do
    begin
      with ListView1.Items[FIndex] do
      begin
        SubItems[3] := FResultMsg;
        SubItems[2] := FormatFileSize(SubItems[0]);
      end;
      Inc(FDoneCount^);
      ProgressBar1.Position := FDoneCount^ * 100 div ListView1.Items.Count;
      if ProgressBar1.Position >= 100 then
        EnableControls(True);
    end;
  finally
    ListItemCS.Release;
  end;
end;

constructor TUPXThread.Create(const AIndex: integer;
  ADoneCount, AThreadCount: PInteger; AForm: TForm1; const AUPXCmd: string;
  const AUPXArgs: TStrings);
begin
  FreeOnTerminate := True;
  FIndex := AIndex;
  FDoneCount := ADoneCount;
  FThreadCount := AThreadCount;
  FForm := AForm;
  FUPXCmd := AUPXCmd;
  FUPXArgs := AUPXArgs;
  Inc(FThreadCount^);
  inherited Create(False);
end;

destructor TUPXThread.Destroy;
begin
  Dec(FThreadCount^);
end;

{ TUPXThreadRunner }

constructor TUPXThreadRunner.Create(AForm: TForm1; const AUPXFile: string);
begin
  FForm := AForm;
  FUPXFile := AUPXFile;
  inherited Create(False);
end;

procedure TUPXThreadRunner.Execute;

  function GenerateUPXArg(const Compress: boolean): TStrings;
  var
    CompressionLvl: longint;
  begin
    Result := TStringList.Create;
    if Compress then
    begin
      CompressionLvl := 9;//FForm.TrackCompLvl.Position;
      if CompressionLvl < 9 then
        Result.Add('-' + IntToStr(CompressionLvl + 1))
      else
        Result.Add('--best');
      {with CompTune do begin
        if LZMA then
          Result.Add('--lzma');
        if Force then
          Result.Add('-f');
        if Brute then
          Result.Add('--brute');
        if UltraBrute then
          Result.Add('--ultra-brute');
      end;
      case Overlay of
        olCopy : Result.Add('--overlay=copy');
        olStrip: Result.Add('--overlay=strip');
        olSkip : Result.Add('--overlay=skip');
      end;
      with Additional do begin
        if AllMethods then
          Result.Add('--all-methods');
        if AllFilters then
          Result.Add('--all-filters');
      end;
      if Other.KeepBackup then}
      Result.Add('-k');
    end
    else
      Result.Add('-d');
  end;

var
  CurrentFile: TListItem;
  FileCount, DoneCount, ThreadCount, NextFileIndex: integer;
  FileIndexCS: TCriticalSection;
begin
  FileCount := FForm.ListView1.Items.Count;
  DoneCount := 0;
  NextFileIndex := 0;
  ThreadCount := 0;
  FileIndexCS := TCriticalSection.Create;
  while DoneCount < FileCount do
  begin
    { create new thread only if not all files have been handled (not
      necessarily processed) and number of running threads hasn't exceed the
      given limit }
    if (NextFileIndex < FileCount) and (ThreadCount < UPXThreadCount) then
    begin
      CurrentFile := FForm.ListView1.Items[NextFileIndex];
      TUPXThread.Create(NextFileIndex, @DoneCount, @ThreadCount,
        FForm, FUPXFile, GenerateUPXArg(CurrentFile.Checked));
      FileIndexCS.Acquire;
      try
        Inc(NextFileIndex);
      finally
        FileIndexCS.Release;
      end;
    end
    else
    begin
      Sleep(100);
    end;
  end;
  { possible problem: when all files have been processed but the last thread
    hasn't been destroyed yet, above loop would terminate and possibly this
    method as well, destroying the stack frame of ThreadCount variable and
    would cause Access Violation because in thread's destructor, this variable
    would be decremented }
  while ThreadCount > 0 do Sleep(100);
  FileIndexCS.Free;
end;

initialization
  {$if FPC_FULLVERSION < 20400}
  {$I FormMain.lrs}
  {$endif}
  ListItemCS := TCriticalSection.Create;

finalization
  ListItemCS.Free;

end.
