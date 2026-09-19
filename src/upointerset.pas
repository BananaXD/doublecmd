{
   Double Commander
   -------------------------------------------------------------------------
   A set of pointers with O(1) Add/Remove/Contains (open addressing hash).

   Used by the file views to check whether a TDisplayFile pointer still
   belongs to the current file list. Replaces TBucketList, whose fixed 256
   buckets degrade to O(n) per operation on directories with 10^5..10^6 files.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.
}

unit uPointerSet;

{$mode objfpc}{$H+}

interface

type

  { TPointerSet }

  TPointerSet = class
  private
    FSlots: array of Pointer;   // nil = empty, TOMBSTONE = deleted
    FCount: Integer;            // live entries
    FUsed: Integer;             // live + deleted entries
    function SlotFor(P: Pointer; out Found: Boolean): Integer;
    procedure Grow;
  public
    constructor Create(ExpectedCount: Integer = 0);
    procedure Add(P: Pointer);
    procedure Remove(P: Pointer);
    function Contains(P: Pointer): Boolean;
    procedure Clear;
    property Count: Integer read FCount;
  end;

implementation

const
  TOMBSTONE = Pointer(1);
  MinCapacity = 64;

function HashPointer(P: Pointer): PtrUInt; inline;
var
  X: PtrUInt;
begin
  // Fibonacci hashing; pointers are 8/16-byte aligned so shift the low bits in.
  X := PtrUInt(P);
  X := X xor (X shr 17);
  {$IFDEF CPU64}
  Result := X * PtrUInt($9E3779B97F4A7C15);
  {$ELSE}
  Result := X * PtrUInt($9E3779B9);
  {$ENDIF}
end;

{ TPointerSet }

constructor TPointerSet.Create(ExpectedCount: Integer);
var
  Capacity: Integer;
begin
  Capacity := MinCapacity;
  // Keep the load factor at or below 1/2.
  while Capacity < ExpectedCount * 2 do
    Capacity := Capacity * 2;
  SetLength(FSlots, Capacity);
end;

function TPointerSet.SlotFor(P: Pointer; out Found: Boolean): Integer;
var
  Mask, FirstTombstone: Integer;
  S: Pointer;
begin
  Mask := Length(FSlots) - 1;
  Result := Integer(HashPointer(P) and PtrUInt(Mask));
  FirstTombstone := -1;
  repeat
    S := FSlots[Result];
    if S = P then
    begin
      Found := True;
      Exit;
    end;
    if S = nil then
    begin
      Found := False;
      if FirstTombstone >= 0 then
        Result := FirstTombstone;
      Exit;
    end;
    if (S = TOMBSTONE) and (FirstTombstone < 0) then
      FirstTombstone := Result;
    Result := (Result + 1) and Mask;
  until False;
end;

procedure TPointerSet.Grow;
var
  Old: array of Pointer;
  i, Idx: Integer;
  Found: Boolean;
begin
  Old := FSlots;
  FSlots := nil;
  SetLength(FSlots, Length(Old) * 2);
  FUsed := 0;
  FCount := 0;
  for i := 0 to High(Old) do
    if (Old[i] <> nil) and (Old[i] <> TOMBSTONE) then
    begin
      Idx := SlotFor(Old[i], Found);
      FSlots[Idx] := Old[i];
      Inc(FUsed);
      Inc(FCount);
    end;
end;

procedure TPointerSet.Add(P: Pointer);
var
  Idx: Integer;
  Found: Boolean;
begin
  if (P = nil) or (P = TOMBSTONE) then Exit;
  Idx := SlotFor(P, Found);
  if Found then Exit;
  if FSlots[Idx] = nil then
    Inc(FUsed);   // reusing a tombstone doesn't add to the used slots
  FSlots[Idx] := P;
  Inc(FCount);
  if FUsed * 2 > Length(FSlots) then
    Grow;
end;

procedure TPointerSet.Remove(P: Pointer);
var
  Idx: Integer;
  Found: Boolean;
begin
  if (P = nil) or (P = TOMBSTONE) then Exit;
  Idx := SlotFor(P, Found);
  if Found then
  begin
    FSlots[Idx] := TOMBSTONE;
    Dec(FCount);
  end;
end;

function TPointerSet.Contains(P: Pointer): Boolean;
begin
  if (P = nil) or (P = TOMBSTONE) then Exit(False);
  SlotFor(P, Result);
end;

procedure TPointerSet.Clear;
begin
  FSlots := nil;
  SetLength(FSlots, MinCapacity);
  FCount := 0;
  FUsed := 0;
end;

end.
