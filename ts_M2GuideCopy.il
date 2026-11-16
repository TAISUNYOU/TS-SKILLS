;; =====================================================================
;; ts_M2GuideCopy.il
;;
;; 템플릿 셀의 M2(PWR) / LG_M2(Guide)를 현재 셀뷰로 복사하고,
;; dir 방향으로 현재 셀뷰 bBox 끝에서 끝까지 늘림.
;;
;; 사용법
;;   ts_M2GuideCopy("TPL_lib" "PWR_A" "Y")              ; dry-run (기본)
;;   ts_M2GuideCopy("TPL_lib" "PWR_A" "Y" ?dryRun nil)  ; 실제 적용
;;
;; 대상 (템플릿 최상위 shape만, instance 내부 무시)
;;   - LG_M2 drawing : rect/path 전부
;;   - M2 drawing    : rect/path 중 net이 현재 셀뷰 cv~>nets에 있는 것
;;       net 판단: a) shape~>net~>name
;;                 b) a가 없으면 shape bBox 안의 M2TXT drawing 라벨 텍스트
;;                    (라벨 이름이 2개 이상이면 SKIP)
;;                 둘 다 없으면 SKIP
;;   - M2TXT drawing : 복사한 M2 shape 안에 있고 같은 net 이름인 라벨
;;
;; 처리
;;   - 템플릿 원점 좌표 그대로 dbCopyFig
;;   - dir "Y": y범위를 bBox 아래~위로 / "X": x범위를 bBox 왼쪽~오른쪽으로
;;     path는 끝 확장(extend 등) 포함한 바깥 경계가 bBox에 붙도록 점 이동
;;   - 복사한 M2는 현재 셀뷰 같은 이름 net에 연결
;;   - 라벨이 줄어든 shape 밖이면 가까운 쪽 끝 안쪽(shape 폭/2)으로 이동
;;   - 기존 shape와 겹쳐도 무시하고 추가
;; =====================================================================

;; ---------------------------------------------------------------------
;; 메인
;; ---------------------------------------------------------------------
procedure( ts_M2GuideCopy( tplLib tplCell dir @key (dryRun t) )
  let( (ok cv res tplCv d bb lo hi cvNets labels m2List guideList
        lp netName inLbls names attach skipNets copiedLbls m2Nets lblNets
        newFig nl net netNames
        (nOther 0) (nSkip 0) (nGuide 0) (nErr 0))

    ;; ---- 점검 ----
    ok = t
    d = when( stringp(dir) upperCase(dir) )
    unless( member(d '("X" "Y"))
      printf("[ERROR] dir는 \"X\" 또는 \"Y\" (입력: %L)\n" dir)
      ok = nil
    )
    when( ok
      res = errset( geGetEditCellView() )
      cv = when( res car(res) )
      cond(
        ( !cv
          printf("[ERROR] 편집 중인 셀뷰 없음\n")
          ok = nil )
        ( !dryRun && cv~>mode == "r"
          printf("[ERROR] %s/%s 읽기 전용. 편집 모드로 연 뒤 실행\n" cv~>libName cv~>cellName)
          ok = nil )
        ( cv~>libName == tplLib && cv~>cellName == tplCell
          printf("[ERROR] 현재 셀뷰가 템플릿과 같음\n")
          ok = nil )
        ( !cv~>bBox
          printf("[ERROR] 현재 셀뷰 bBox 없음 (빈 셀)\n")
          ok = nil )
      )
    )
    when( ok
      res = errset( dbOpenCellViewByType(tplLib tplCell "layout" nil "r") )
      tplCv = when( res car(res) )
      unless( tplCv
        printf("[ERROR] 템플릿 열기 실패: %L/%L layout\n" tplLib tplCell)
        ok = nil
      )
    )

    when( ok
      ;; ---- 기준 범위 (복사 전 bBox) ----
      bb = cv~>bBox
      if( d == "Y" then
        lo = cadr(car(bb))  hi = cadr(cadr(bb))
      else
        lo = car(car(bb))   hi = car(cadr(bb))
      )

      ;; ---- 현재 셀뷰 net 이름 ----
      cvNets = nil
      foreach( n cv~>nets cvNets = cons(n~>name cvNets) )

      ;; ---- 템플릿 최상위 shape 분류 ----
      foreach( s tplCv~>shapes
        lp = list(s~>layerName s~>purpose)
        cond(
          ( lp == '("M2TXT" "drawing")
            when( s~>objType == "label" labels = cons(s labels) ) )
          ( lp == '("M2" "drawing")
            if( member(s~>objType '("rect" "path"))
              m2List = cons(s m2List)
              nOther = nOther + 1 ) )
          ( lp == '("LG_M2" "drawing")
            if( member(s~>objType '("rect" "path"))
              guideList = cons(s guideList)
              nOther = nOther + 1 ) )
        )
      )

      printf("\n===== ts_M2GuideCopy [%s] %s/%s -> %s/%s / dir %s / 범위 %L~%L =====\n"
        if(dryRun "DRY-RUN" "APPLY") tplLib tplCell cv~>libName cv~>cellName d lo hi)

      ;; ---- Guide ----
      foreach( s guideList
        unless( errset(
            if( !ts_M2AlongDir(s d) then
              nSkip = nSkip + 1
              printf("[SKIP] LG_M2 %L: dir 방향 path 아님\n" s~>bBox)
            else
              unless( dryRun
                newFig = dbCopyFig(s cv)
                ts_M2Stretch(newFig d lo hi)
              )
              nGuide = nGuide + 1
            )
            t )
          nErr = nErr + 1
          printf("[ERROR] LG_M2 %L: 처리 실패, 다음으로 진행\n" s~>bBox)
        )
      )

      ;; ---- PWR (M2 + 라벨) ----
      foreach( s m2List
        unless( errset(
            prog( ()
              unless( ts_M2AlongDir(s d)
                nSkip = nSkip + 1
                printf("[SKIP] M2 %L: dir 방향 path 아님\n" s~>bBox)
                return(nil)
              )
              inLbls = setof( lb labels ts_M2PtInBox(lb~>xy s~>bBox) )

              ;; a) shape net
              netName = when( s~>net s~>net~>name )
              ;; b) 라벨
              unless( netName
                names = nil
                foreach( lb inLbls
                  unless( member(lb~>theLabel names) names = cons(lb~>theLabel names) )
                )
                cond(
                  ( length(names) == 1 netName = car(names) )
                  ( length(names) > 1
                    nSkip = nSkip + 1
                    printf("[SKIP] M2 %L: 라벨 이름 여러 개 %L\n" s~>bBox names)
                    return(nil) )
                )
              )
              unless( netName
                nSkip = nSkip + 1
                printf("[SKIP] M2 %L: net 없음 (shape net/라벨 둘 다 없음)\n" s~>bBox)
                return(nil)
              )
              unless( member(netName cvNets)
                nSkip = nSkip + 1
                unless( member(netName skipNets) skipNets = cons(netName skipNets) )
                return(nil)
              )

              attach = setof( lb inLbls lb~>theLabel == netName && !memq(lb copiedLbls) )

              unless( dryRun
                newFig = dbCopyFig(s cv)
                ts_M2Stretch(newFig d lo hi)
                net = dbFindNetByName(cv netName)
                if( net then
                  dbAddFigToNet(newFig net)
                else
                  printf("[ERROR] %s: net 찾기 실패, 연결 안 됨\n" netName)
                  nErr = nErr + 1
                )
              )
              m2Nets = cons(netName m2Nets)

              foreach( lb attach
                copiedLbls = cons(lb copiedLbls)
                if( errset(
                      unless( dryRun
                        nl = dbCopyFig(lb cv)
                        ts_M2LabelInside(nl newFig d)
                      )
                      t ) then
                  lblNets = cons(netName lblNets)
                else
                  nErr = nErr + 1
                  printf("[ERROR] 라벨 %s %L: 복사 실패\n" netName lb~>xy)
                )
              )
              return(t)
            )
            t )
          nErr = nErr + 1
          printf("[ERROR] M2 %L: 처리 실패, 다음으로 진행\n" s~>bBox)
        )
      )

      errset( dbClose(tplCv) )

      ;; ---- 요약 ----
      printf("\n")
      netNames = nil
      foreach( n append(m2Nets lblNets)
        unless( member(n netNames) netNames = cons(n netNames) )
      )
      foreach( n reverse(netNames)
        printf("[%s] M2 %d개 / 라벨 %d개\n" n
          length(setof(x m2Nets x == n)) length(setof(x lblNets x == n)))
      )
      printf("[GUIDE] LG_M2 %d개\n" nGuide)
      when( skipNets
        printf("[SKIP] 현재 셀뷰에 없는 net: %L\n" reverse(skipNets)))
      when( nOther > 0
        printf("[SKIP] rect/path 아닌 M2/LG_M2 shape %d개 (복사 안 함)\n" nOther))
      printf("[전체] M2 %d개 / 라벨 %d개 / GUIDE %d개 / SKIP %d개 / ERROR %d개%s\n"
        length(m2Nets) length(lblNets) nGuide nSkip + nOther nErr
        if(dryRun " (예정)" ""))
      when( dryRun
        printf("-> 확인 후 실제 적용: ts_M2GuideCopy(%L %L %L ?dryRun nil)\n" tplLib tplCell dir))
    )
    t
  )
)

;; ---------------------------------------------------------------------
;; 유틸: 복사한 rect/path를 dir 방향으로 lo~hi까지 늘림
;;       path는 끝 확장 길이를 빼서 바깥 경계가 lo/hi에 붙게 함
;; ---------------------------------------------------------------------
procedure( ts_M2Stretch( fig d lo hi )
  let( (box pts p1 pN w st e1 eN c1 cN)
    if( fig~>objType == "rect" then
      box = fig~>bBox
      fig~>bBox = if( d == "Y"
        list( list(car(car(box)) lo) list(car(cadr(box)) hi) )
        list( list(lo cadr(car(box))) list(hi cadr(cadr(box))) )
      )
    else
      pts = fig~>points
      p1  = car(pts)
      pN  = car(last(pts))
      w   = fig~>width
      st  = fig~>pathStyle
      e1  = cond( (st == "truncate" 0) (st == "variable" fig~>beginExt) (t w / 2.0) )
      eN  = cond( (st == "truncate" 0) (st == "variable" fig~>endExt)   (t w / 2.0) )
      if( d == "Y" then
        c1 = cadr(p1)  cN = cadr(pN)
      else
        c1 = car(p1)   cN = car(pN)
      )
      if( c1 <= cN then
        c1 = lo + e1  cN = hi - eN
      else
        c1 = hi - e1  cN = lo + eN
      )
      fig~>points = if( d == "Y"
        list( list(car(p1) c1) list(car(pN) cN) )
        list( list(c1 cadr(p1)) list(cN cadr(pN)) )
      )
    )
    t
  )
)

;; ---------------------------------------------------------------------
;; 유틸: 라벨이 shape 밖(dir 방향)이면 가까운 쪽 끝 안쪽(폭/2)으로 이동
;; ---------------------------------------------------------------------
procedure( ts_M2LabelInside( lbl fig d )
  let( (nb pt c lo hi m)
    nb = fig~>bBox
    pt = lbl~>xy
    if( d == "Y" then
      c = cadr(pt)  lo = cadr(car(nb))  hi = cadr(cadr(nb))
      m = (car(cadr(nb)) - car(car(nb))) / 2.0
    else
      c = car(pt)   lo = car(car(nb))   hi = car(cadr(nb))
      m = (cadr(cadr(nb)) - cadr(car(nb))) / 2.0
    )
    when( c < lo || c > hi
      c = if( c < lo lo + m hi - m )
      lbl~>xy = if( d == "Y" list(car(pt) c) list(c cadr(pt)) )
    )
    t
  )
)

;; ---------------------------------------------------------------------
;; 유틸: path가 dir 방향 직선인지 (rect는 항상 t)
;; ---------------------------------------------------------------------
procedure( ts_M2AlongDir( s d )
  let( (p1 pN)
    if( s~>objType != "path" then
      t
    else
      p1 = car(s~>points)
      pN = car(last(s~>points))
      if( d == "Y" car(p1) == car(pN) cadr(p1) == cadr(pN) )
    )
  )
)

;; ---------------------------------------------------------------------
;; 유틸: 점이 box 안(경계 포함)인지
;; ---------------------------------------------------------------------
procedure( ts_M2PtInBox( pt box )
  car(pt)  >= car(car(box))  && car(pt)  <= car(cadr(box)) &&
  cadr(pt) >= cadr(car(box)) && cadr(pt) <= cadr(cadr(box))
)
