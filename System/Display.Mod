MODULE Display;
(* stub module to create necessary interface; -- noch *)
IMPORT Objects;
TYPE
  Color* = LONGINT;

  Pattern* = LONGINT;

  List = POINTER TO ListDesc;
  ListDesc = RECORD
    next: List;
    data: POINTER TO ARRAY OF CHAR;
  END;

  Frame* = POINTER TO FrameDesc;  (** Base type of all displayable objects. *)
  FrameDesc* = RECORD (Objects.ObjDesc)
    next*, dsc*: Frame;  (** Sibling, child pointers. *)
    X*, Y*, W*, H*: INTEGER  (** Coordinates. *)
  END;

  FrameMsg* = RECORD (Objects.ObjMsg)  (** Base type of messages sent to frames. *)
    F*: Frame; (** Message target, NIL for broadcast. *)
    x*, y*: INTEGER;  (** Message origin. *)
    res*: INTEGER  (** Result code: <0 = error or no response, >=0 response. *)
  END;

  ControlMsg* = RECORD (FrameMsg)
    id*: INTEGER  (** remove, suspend, restore. *)
  END;

  ModifyMsg* = RECORD (FrameMsg)  (** Change coordinates in container frame. *)
    id*: INTEGER;  (** reduce, extend, move. *)
    mode*: INTEGER;  (** Modes display, state. *)
    dX*, dY*, dW*, dH*: INTEGER;  (** Change from old coordinates (delta). *)
    X*, Y*, W*, H*: INTEGER  (** New coordinates. *)
  END;

  DisplayMsg* = RECORD (FrameMsg)  (** Display a frame, a part of it or its contents. *)
    device*: INTEGER;  (** screen, printer *)
    id*: INTEGER;  (** full, area, contents. *)
    u*, v*, w*, h*: INTEGER  (** Area to be restored. *)
  END;

  LocateMsg* = RECORD (FrameMsg)  (** Locate frame in display space. *)
    loc*: Frame;  (** Result. *)
    X*, Y*: INTEGER;  (** Absolute location. *)
    u*, v*: INTEGER  (** Relative coordinates in loc. *)
  END;

  SelectMsg* = RECORD (FrameMsg)  (** Selection control. *)
    id*: INTEGER;  (** get, set, reset. *)
    time*: LONGINT;  (** Time of selection. *)
    sel*: Frame;  (** Parent of selection. *)
    obj*: Objects.Object  (** List of objects involved, linked with slink. *)
  END;

  ConsumeMsg* = RECORD (FrameMsg)  (** Drop, integrate frames. *)
    id*: INTEGER;  (** drop, integrate. *)
    u*, v*: INTEGER;  (** Relative coordinates in destination when drop. *)
    obj*: Objects.Object  (** List of objects to be consumed, linked with slink. *)
  END;

    SetupRes0= RECORD
        res, n: CHAR;
        major, minor: INTEGER;
        len: INTEGER;
    END;
    SetupRes1= RECORD
        rnr, ridbase, ridmask, motionbuffersize: LONGINT;
        lenvendor, maxreqlen: INTEGER;
        noscreens, noformats: CHAR;
        imgbyteorder, bmbitorder: CHAR;
        scanliunrunit, scanlinepad: CHAR;
        minkeycode, maxkeycode: CHAR;
        unused: LONGINT;
    END;

    Format= RECORD
        depth, bpp, slpad: CHAR;
        p0, p1, p2, p3, p4: CHAR;
    END;

    Screen= RECORD
        root*, dcolormap, wpixel, bpixel: LONGINT;
        cimasks: LONGINT;
        width, height: INTEGER;
        wmm, hmm: INTEGER;
        minimaps, maximaps: INTEGER;
        rvisual: LONGINT;
        bstores, sunders, rdepth, ndepth: CHAR;
    END;
    DepthT= RECORD
        depth, pad0: CHAR;
        nvisualtypes: INTEGER;
        pad: LONGINT;
    END;
    VisualT= RECORD
        id: LONGINT;
        class, bprgbvalue: CHAR;
        cmapentries: INTEGER;
        rmask, gmask, bmask: LONGINT;
        pad: LONGINT;
    END;

  MsgProc* = PROCEDURE (VAR M: FrameMsg);

VAR
  Unit*: LONGINT; (** RasterUnit = Unit/36000 mm *)
  Zoom*: LONGINT;  (** Zoom factor for HiDPI displays, currently only X11 with XShm *)
  Left*, (** Left margin of black-and-white screen. *)
  ColLeft*, (** Left margin of secondary display, often same as Left. *)
  Bottom*, (** Bottom of primary map. *)
  UBottom*, (** Bottom of offscreen area (negative), 0 if not supported. *)
  Width*, (** Display width. *)
  Height*: INTEGER; (** Display height. *)

  arrow*,   (** Oberon cursor. *)
  star*,   (** Star marker to mark documents and viewers. *)
  cross*,   (** Insertion marker. *)
  downArrow*,   (** Marker to indicate disk operation. *)
  hook*,  (** Text caret pattern. *)
  grey0*, grey1*, grey2*, ticks*, solid*: Pattern;  (** Simulated grey levels. *)
  Broadcast*: MsgProc;  (** Message broadcast to all frames in the display space. *)
  clipX, clipY, clipXR, clipYT: LONGINT;  (* bottom left corner & top right corner, in Oberon coordinates *)
  pattern: List;

  bytes, displayFormat, linelength : LONGINT;
  palette: ARRAY 256 OF LONGINT;

(* X11 *)
  cid, pid, gcpid, wid*, iwid, gcid, shmseg: LONGINT;
  scn*: Screen;
  r1data: SetupRes1;

  ShmReqCode, BigReqCode, shmid: LONGINT;

  x11Keymap: POINTER TO ARRAY  OF ARRAY OF LONGINT;

  xkspkc: LONGINT;
  tcp, port: LONGINT;    (*  adr and port of x11 server over ssh  *)

  xfd: LONGINT;  (* X11 socket or frambuffer fd *)
  fbuf: POINTER TO ARRAY OF CHAR;  (* buffer for X11 without SHM *)
  xrv: POINTER TO ARRAY OF LONGINT;  (* X11 request vector *)
  rmr, rmw, gmr, gmw, bmr, bmw: LONGINT;  (* color mask right, color mask width *)

  (** TransferFormat() return values.  value DIV 8 = bytes per pixel.  portable, release >= 2.4*)
  CONST unknown* = 0; index8* = 8; color555* = 16; color565* = 17; color664* = 18; color888* = 24; color8888* = 32;



(* from OLR.Display.Mod *)
(** Returns the color palette depth for the specified display region. Typical values are 1, 4 and 8 (not larger). *)
PROCEDURE Depth*(x: LONGINT): INTEGER;
BEGIN
  RETURN  8
END Depth;

PROCEDURE GetColor*(col: Color; VAR red, green, blue: INTEGER);
BEGIN
  IF col >= 0 THEN col := palette[col] END;
  red:=SHORT(ASH( ASH(col, -rmr), 8-rmw) MOD 256);
  green:=SHORT(ASH( ASH(col, -gmr), 8-gmw) MOD 256);
  blue:=SHORT(ASH( ASH(col, -bmr), 8-bmw) MOD 256);
END GetColor;


(** Return true color with specified components. 0 <= red, green, blue < 256.  Not all display regions support true color values, see TrueColor(). *)
PROCEDURE RGB*(red, green, blue: LONGINT): Color;  (** portable, release >= 2.4 *)
BEGIN
  RETURN MIN(LONGINT) + ASH( ASH(red, rmw-8), rmr)+ ASH( ASH(green, gmw-8), gmr)+ ASH( ASH(blue, bmw-8), bmr)
END RGB;

(** Returns TRUE iff the specified display region supports true color values. *)
PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;  (** portable, release >= 2.4 *)
BEGIN
  RETURN TRUE
END TrueColor;

(** Return the TransferBlock format of a display region. *)
PROCEDURE TransferFormat*(x: LONGINT): LONGINT;  (** portable, release >= 2.4 *)
BEGIN
  (* these strings are taken from OLR.Display.InitFB procedure *)
(*   IF v.bitsperpixel=16 THEN displayFormat:=color565; bytes:=2; DrawPattern:=DrawPattern16;
  ELSIF v.bitsperpixel=24 THEN displayFormat:=color8888; bytes:=4; DrawPattern:=DrawPattern32;
  ELSIF v.bitsperpixel=32 THEN displayFormat:=color8888; bytes:=4; DrawPattern:=DrawPattern32;
*)
  displayFormat := color8888;
  bytes := 4;
  RETURN displayFormat;
END TransferFormat;

BEGIN
  Zoom:=1;
  Left := 0;  ColLeft := 0;  Bottom := 0;  UBottom := 0; Unit := 10000;
  tcp:=0; ShmReqCode:= 0;
  pattern := NIL;
  (* additions *)
  bytes := 4;
  rmr := 0; gmr := 0; bmr := 0; rmw := 0; gmw := 0; bmw := 0;
END Display.
