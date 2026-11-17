;; =====================================================================
;; ts_ViaRepeat.il
;;
;; 기준 VM1C via 1개를 바탕으로, 그 아래 MOS PCell에서 같은 역할
;; (D면 D, S면 S) finger 전체에 VM1C를 mosaic으로 박음.
;;
;; 사용법 (layout 창을 현재 창으로 두고 실행)
;;   1) 기존 스킬로 M0∩M1 자리에 VM1C 1개 박기 (선택된 상태로 남음)
;;   2) ts_ViaRepeat()               ; dry-run: 박힐 위치를 하이라이트
;;      ts_ViaRepeat(?dryRun nil)    ; 실제 생성
;;      ts_ViaRepeatClear()          ; dry-run 하이라이트 지우기
;;   옵션: ?absorbRef nil  기준 via는 그대로 두고 나머지만 박음
;;         ?depth 3        MOS를 찾을 하위 계층 깊이
;;         ?viaCell "VM1C" ?m0Layer "M0" ?m1Layer "M1" ?terms '("D" "S")
;;
;; 동작
;;   - 기준 via 중심점에서 계층을 따라 내려가며 MOS를 찾음
;;     (현재 셀뷰 또는 ?depth 단계 아래까지, transform 누적)
;;     MOS 판정: PCell이고 terminal "D"/"S"에 M0 pin이 있음
;;     (중간 셀에 D/S pin이 있어도 PCell이 아니면 MOS로 안 봄)
;;   - MOS의 D/S M0 pin으로 finger 위치와 역할을 판단
;;     (pin이 strip 끝에 작게 있어도 finger 방향 좌표만 쓰므로 무관)
;;   - via는 현재 셀뷰 최상위에 생성, M1 파워라인도 최상위만 봄
;;   - 기준 via를 같은 역할 finger 위치로 평행이동한 자리 중
;;     아래를 모두 만족하는 곳만 박음
;;       a) 그 자리에 MOS 내부 M0가 있음
;;       b) 기준 via와 같은 M1 shape(파워라인) 위
;;       c) VM1C(instance/mosaic)가 아직 없음
;;   - 등간격으로 이어진 구간마다 mosaic 1개 (1개짜리 구간은 dbCopyFig)
;;     VM1C PCell: 기준 via 파라미터로 mosaic 생성 후, master가 기준 via와
;;     같은 submaster인지(= 파라미터 동일) 확인. 다르면 지우고 [ERROR]
;;   - ?absorbRef t(기본): 기준 via도 mosaic에 포함하고 원래 것은 삭제
;;     (기준 via 때문에 mosaic이 둘로 끊기지 않게). 생성 실패가 하나라도
;;     있으면 기준 via는 지우지 않음
;;
;; 주의
;;   - mosaic 안의 via 하나만 지우려면 flatten 필요
;;   - 탐색 경로 중간의 mosaic(instance array) 내부는 탐색 안 함 ([WARN])
;; =====================================================================

unless( boundp('tsViaRepeatHl) tsViaRepeatHl = nil )

;; ---------------------------------------------------------------------
;; 메인
;; ---------------------------------------------------------------------
procedure( ts_ViaRepeat( @key (dryRun t) (absorbRef t) (depth 3) (viaCell "VM1C")
                              (m0Layer "M0") (m1Layer "M1") (terms '("D" "S")) )
  let( (ok cv res sel ref bb c0 viaW viaH offX offY g eps found mos mosXf mosPath match
        axisX role refC roleCs m0Boxes m1Ref existing o c
        targets pitch runs cur n rows cols rowSp colSp obj newObjs hl
        (nExist 0) (nNoM0 0) (nNoM1 0) (nErr 0))

    ts_ViaRepeatClear()

    ;; ---- 점검 ----
    ok = t
    res = errset( geGetEditCellView() )
    cv = when( res car(res) )
    cond(
      ( !cv
        printf("[ERROR] 편집 중인 셀뷰 없음\n")
        ok = nil )
      ( !dryRun && cv~>mode == "r"
        printf("[ERROR] %s/%s 읽기 전용. 편집 모드로 연 뒤 실행\n" cv~>libName cv~>cellName)
        ok = nil )
    )
    when( ok
      sel = setof( x geGetSelSet() x~>objType == "inst" && x~>cellName == viaCell )
      unless( length(sel) == 1
        printf("[ERROR] 기준 %s instance를 1개만 선택하세요 (현재 %d개)\n" viaCell length(sel))
        ok = nil
      )
    )

    ;; ---- 기준 via / 그리드 ----
    when( ok
      ref  = car(sel)
      bb   = ref~>bBox
      c0   = ts_VRCenter(bb)
      viaW = xCoord(cadr(bb)) - xCoord(car(bb))
      viaH = yCoord(cadr(bb)) - yCoord(car(bb))
      offX = xCoord(c0) - xCoord(ref~>xy)
      offY = yCoord(c0) - yCoord(ref~>xy)
      res = errset( techGetMfgGridResolution( techGetTechFile(cv) ) )
      g   = if( res && car(res) car(res) 0.001 )
      eps = g / 2.0

      ;; ---- 기준 via 아래 MOS 찾기 (계층 탐색) ----
      res = errset( ts_VRFindMos( cv list( list(0 0) "R0" 1.0 ) c0 terms m0Layer
                                  viaCell depth nil eps ) )
      found = when( res car(res) )
      unless( res
        printf("[ERROR] MOS 계층 탐색 중 에러\n") )
      unless( found
        printf("[ERROR] 기준 via 아래 %d단계 안에서 %L %s pin으로 역할을 판단할 MOS PCell을 못 찾음\n"
               depth terms m0Layer)
        ok = nil
      )
    )

    when( ok
      mos     = nth(0 found)
      mosXf   = nth(1 found)
      match   = nth(2 found)
      mosPath = nth(3 found)
      axisX  = nth(0 match)
      role   = nth(1 match)
      refC   = nth(2 match)
      roleCs = nth(3 match)
      m0Boxes = ts_VRShapes( mos~>master mosXf m0Layer 5 )
      m1Ref   = dbGetTrueOverlaps( cv list(c0 c0) list(m1Layer) )
      cond(
        ( !exists( b m0Boxes ts_VRInBox(c0 b eps) )
          printf("[ERROR] %s 안에서 기준 via 위치의 %s를 못 찾음\n" mosPath m0Layer)
          ok = nil )
        ( !m1Ref
          printf("[ERROR] 기준 via 중심 %L에 최상위 %s shape 없음\n" c0 m1Layer)
          ok = nil )
      )
    )

    ;; ---- 대상 위치 계산 ----
    when( ok
      existing = ts_VRViaOrigins( cv viaCell if( absorbRef ref nil ) )
      foreach( fc roleCs
        o = ts_VRShift( ref~>xy fc - refC axisX )
        o = if( axisX
              list( ts_VRSnap(xCoord(o) g) yCoord(o) )
              list( xCoord(o) ts_VRSnap(yCoord(o) g) ) )
        c = list( xCoord(o) + offX  yCoord(o) + offY )
        cond(
          ( exists( e existing ts_VRNear(e o eps) )
            nExist++ )
          ( !exists( b m0Boxes ts_VRInBox(c b eps) )
            nNoM0++ )
          ( !exists( s dbGetTrueOverlaps( cv list(c c) list(m1Layer) ) memq(s m1Ref) )
            nNoM1++ )
          ( t
            targets = cons( o targets ) )
        )
      )
      targets = sort( targets lambda( (a b) ts_VRAx(a axisX) < ts_VRAx(b axisX) ) )

      ;; ---- 등간격 구간으로 나누기 ----
      pitch = ts_VRMinGap( foreach( mapcar t1 targets ts_VRAx(t1 axisX) ) )
      foreach( t1 targets
        if( cur && pitch
            && abs( ts_VRAx(t1 axisX) - ts_VRAx(car(cur) axisX) - pitch ) < eps then
          cur = cons( t1 cur )
        else
          when( cur runs = cons( reverse(cur) runs ) )
          cur = list( t1 )
        )
      )
      when( cur runs = cons( reverse(cur) runs ) )
      runs = reverse(runs)

      ;; ---- 출력 ----
      printf("[REF] %s @ %L / MOS %s (%s) / 역할 %s / finger 방향 %s\n"
             ref~>name ref~>xy mosPath mos~>cellName role if( axisX "X" "Y" ))
      printf("[INFO] %s finger %d개: 박을 곳 %d / 이미 via %d / M0 없음 %d / M1 밖 %d\n"
             role length(roleCs) length(targets) nExist nNoM0 nNoM1)
      foreach( run runs
        if( cdr(run) then
          printf("  [MOSAIC] %d개 pitch %g 시작 %L\n" length(run) pitch car(run))
        else
          printf("  [INST]   1개 %L\n" car(run))
        )
      )

      cond(
        ( !targets
          printf("박을 곳 없음\n") )

        ;; ---- dry-run: 하이라이트만 ----
        ( dryRun
          res = errset(
            progn(
              hl = geCreateHilightSet( hiGetCurrentWindow() list(m1Layer "drawing") )
              foreach( t1 targets
                geAddHilightRectangle( hl
                  ts_VRShiftBox( bb xCoord(t1) - xCoord(ref~>xy) yCoord(t1) - yCoord(ref~>xy) ) )
              )
              hl~>enable = t
              tsViaRepeatHl = hl
              t ) )
          if( res then
            printf("dry-run: 박힐 위치 하이라이트. 지우기 ts_ViaRepeatClear() / 실제 생성 ?dryRun nil\n")
          else
            printf("dry-run: (하이라이트 실패 - 위 좌표 참고) 실제 생성 ?dryRun nil\n")
          )
        )

        ;; ---- 실제 생성 ----
        ( t
          foreach( run runs
            n = length(run)
            if( axisX then
              rows = 1  cols = n  rowSp = viaH  colSp = or( pitch viaW )
            else
              rows = n  cols = 1  rowSp = or( pitch viaH )  colSp = viaW
            )
            obj = car( errset( ts_VRCreate( cv ref car(run) rows cols rowSp colSp ) ) )
            if( obj then
              newObjs = cons( obj newObjs )
            else
              nErr++
              printf("[ERROR] %d개 구간 생성 실패 @ %L\n" n car(run))
            )
          )
          when( absorbRef
            if( nErr == 0 then
              dbDeleteObject(ref)
            else
              printf("[WARN] 생성 실패가 있어 기준 via는 남겨둠\n")
            )
          )
          geDeselectAll()
          geSelectFigs( newObjs )
          printf("생성 %d개 (mosaic/instance) / 실패 %d개\n" length(newObjs) nErr)
        )
      )
    )
    ok
  )
)

;; dry-run 하이라이트 지우기
procedure( ts_ViaRepeatClear()
  when( tsViaRepeatHl
    errset( tsViaRepeatHl~>enable = nil )
    tsViaRepeatHl = nil
  )
  t
)

;; ---------------------------------------------------------------------
;; 유틸
;; ---------------------------------------------------------------------
;; master 안에서 c0(최상위 좌표)를 덮는 instance를 따라 내려가며 MOS 찾기
;;   xf   : master 좌표 -> 최상위 좌표 transform
;;   depth: 더 내려갈 수 있는 단계 수
;; => list( mosInst mosXf match "I0/I3/M5" ) / 못 찾으면 nil
procedure( ts_VRFindMos( master xf c0 terms m0Layer viaCell depth path eps )
  let( (found ixf p match)
    foreach( inst master~>instances
      when( !found && inst~>objType == "inst" && inst~>cellName != viaCell
            && ts_VRInBox( c0 dbTransformBBox( inst~>bBox xf ) eps )
        ixf = dbConcatTransform( inst~>transform xf )
        p   = if( path strcat( path "/" inst~>name ) inst~>name )
        if( inst~>master~>superMaster then
          ;; PCell: MOS인지 확인만 하고 안으로는 안 들어감
          match = car( errset( ts_VRMatch( inst ixf c0 terms m0Layer ) ) )
          when( match found = list( inst ixf match p ) )
        else
          when( depth > 0
            found = ts_VRFindMos( inst~>master ixf c0 terms m0Layer viaCell
                                  depth - 1 p eps )
          )
        )
      )
    )
    unless( found
      foreach( m master~>mosaics
        when( car( errset( ts_VRInBox( c0 dbTransformBBox( m~>bBox xf ) eps ) ) )
          printf("[WARN] %s 안 mosaic %L이 기준 via를 덮음 - mosaic 내부는 탐색 안 함\n"
                 or( path "(top)" ) m~>name)
        )
      )
    )
    found
  )
)

;; MOS instance의 D/S pin으로 역할 판단 (ixf: MOS 좌표 -> 최상위 좌표)
;; => list( axisX role refC roleCs ) / 판단 못 하면 nil
;;    axisX : finger가 X 방향으로 늘어서 있으면 t
;;    refC  : 기준 via finger의 finger 방향 좌표
;;    roleCs: 같은 역할 finger들의 finger 방향 좌표 (중복 제거, 오름차순)
procedure( ts_VRMatch( inst ixf c0 terms m0Layer )
  let( (pins xs ys axisX fp best bd dd role)
    pins = ts_VRPins( inst ixf terms m0Layer )
    when( pins
      xs = foreach( mapcar p pins xCoord(cadr(p)) )
      ys = foreach( mapcar p pins yCoord(cadr(p)) )
      axisX = apply('max xs) - apply('min xs) >= apply('max ys) - apply('min ys)
      fp = ts_VRMinGap( ts_VRUniq( foreach( mapcar p pins ts_VRAx(cadr(p) axisX) ) ) )
      foreach( p pins
        dd = abs( ts_VRAx(cadr(p) axisX) - ts_VRAx(c0 axisX) )
        when( !bd || dd < bd
          bd = dd
          best = p
        )
      )
      ;; 가장 가까운 pin이 finger 간격의 절반 안에 있어야 같은 finger
      when( !fp || bd < fp / 2.0
        role = car(best)
        list( axisX role ts_VRAx(cadr(best) axisX)
              ts_VRUniq( foreach( mapcar p setof( q pins car(q) == role )
                           ts_VRAx(cadr(p) axisX) ) ) )
      )
    )
  )
)

;; PCell master의 terms pin 중 m0Layer인 것 => list( (termName 중심점) ... ) 최상위 좌표
procedure( ts_VRPins( inst ixf terms m0Layer )
  let( (out fig)
    foreach( term inst~>master~>terminals
      when( member( term~>name terms )
        foreach( pin term~>pins
          fig = pin~>fig
          when( fig && fig~>layerName == m0Layer
            out = cons( list( term~>name
                              ts_VRCenter( dbTransformBBox( fig~>bBox ixf ) ) )
                        out )
          )
        )
      )
    )
    out
  )
)

;; master 안 layer shape bBox 전부 (하위 instance depth까지), 최상위 좌표
procedure( ts_VRShapes( master xf layer depth )
  let( (out)
    foreach( s master~>shapes
      when( s~>objType != "label" && s~>layerName == layer
        out = cons( dbTransformBBox( s~>bBox xf ) out )
      )
    )
    when( depth > 0
      foreach( i master~>instances
        out = nconc( ts_VRShapes( i~>master dbConcatTransform( i~>transform xf )
                                  layer depth - 1 )
                     out )
      )
    )
    out
  )
)

;; 셀뷰에 있는 viaCell origin 전부 (instance + mosaic 각 칸), skip은 제외
procedure( ts_VRViaOrigins( cv viaCell skip )
  let( (out xy)
    foreach( i cv~>instances
      when( i~>objType == "inst" && i~>cellName == viaCell && !eq(i skip)
        out = cons( i~>xy out )
      )
    )
    foreach( m cv~>mosaics
      errset(
        when( m~>cellName == viaCell
          xy = m~>xy
          for( r 0 m~>rows - 1
            for( k 0 m~>columns - 1
              out = cons( list( xCoord(xy) + k * m~>uX  yCoord(xy) + r * m~>uY ) out )
            )
          )
        )
      )
    )
    out
  )
)

;; 기준 via와 같은 via를 xy(origin)에 생성
;;   1개   : dbCopyFig (파라미터 그대로 복사)
;;   여러 개: mosaic. PCell이면 기준 파라미터로 만들고, master가 기준과
;;           같은 submaster인지 확인 (다르면 지우고 nil)
procedure( ts_VRCreate( cv ref xy rows cols rowSp colSp )
  let( (sm params obj)
    if( rows * cols == 1 then
      dbCopyFig( ref cv list( list( xCoord(xy) - xCoord(ref~>xy)
                                    yCoord(xy) - yCoord(ref~>xy) )
                              "R0" 1.0 ) )
    else
      sm = ref~>master~>superMaster
      when( sm
        params = foreach( mapcar p ref~>prop list( p~>name p~>valueType p~>value ) )
        obj = car( errset( dbCreateParamSimpleMosaic( cv sm nil xy ref~>orient
                             rows cols rowSp colSp params ) ) )
        obj = ts_VRVerify( obj ref )
      )
      unless( obj
        obj = car( errset( dbCreateSimpleMosaic( cv ref~>master nil xy ref~>orient
                             rows cols rowSp colSp ) ) )
        obj = ts_VRVerify( obj ref )
      )
      obj
    )
  )
)

;; 생성한 mosaic의 master가 기준 via master와 같은지 확인
;; 다르면 지우고 nil, 확인 못 하면 [WARN] 후 그대로 둠
procedure( ts_VRVerify( obj ref )
  let( (m)
    when( obj
      m = or( car( errset( obj~>master ) )
              car( errset( car( obj~>instanceList )~>master ) ) )
      cond(
        ( !m
          printf("[WARN] mosaic master 확인 불가 - 파라미터 눈으로 확인 필요\n")
          obj )
        ( eq( m ref~>master )
          obj )
        ( t
          printf("[WARN] mosaic 파라미터가 기준 via와 달라 삭제\n")
          dbDeleteObject(obj)
          nil )
      )
    )
  )
)

procedure( ts_VRCenter( bb )
  list( (xCoord(car(bb)) + xCoord(cadr(bb))) / 2.0
        (yCoord(car(bb)) + yCoord(cadr(bb))) / 2.0 )
)

procedure( ts_VRAx( pt axisX )
  if( axisX xCoord(pt) yCoord(pt) )
)

procedure( ts_VRShift( pt d axisX )
  if( axisX
    list( xCoord(pt) + d yCoord(pt) )
    list( xCoord(pt) yCoord(pt) + d ) )
)

procedure( ts_VRShiftBox( bb dx dy )
  list( list( xCoord(car(bb)) + dx  yCoord(car(bb)) + dy )
        list( xCoord(cadr(bb)) + dx yCoord(cadr(bb)) + dy ) )
)

procedure( ts_VRInBox( pt bb eps )
  xCoord(pt) >= xCoord(car(bb)) - eps && xCoord(pt) <= xCoord(cadr(bb)) + eps &&
  yCoord(pt) >= yCoord(car(bb)) - eps && yCoord(pt) <= yCoord(cadr(bb)) + eps
)

procedure( ts_VRNear( a b eps )
  abs( xCoord(a) - xCoord(b) ) < eps && abs( yCoord(a) - yCoord(b) ) < eps
)

procedure( ts_VRSnap( v g )
  round( v / g ) * g
)

;; 숫자 리스트 정렬 + 거의 같은 값 제거
procedure( ts_VRUniq( vals )
  let( (out)
    foreach( v sort( copy(vals) 'lessp )
      unless( out && abs( v - car(out) ) < 0.0001
        out = cons( v out )
      )
    )
    reverse(out)
  )
)

;; 정렬했을 때 이웃 간격 중 최소 (2개 미만이면 nil)
procedure( ts_VRMinGap( vals )
  let( (s m d)
    s = sort( copy(vals) 'lessp )
    while( cdr(s)
      d = cadr(s) - car(s)
      when( !m || d < m m = d )
      s = cdr(s)
    )
    m
  )
)
