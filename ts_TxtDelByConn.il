;;=====================================================================
;; ts_TxtDelByConn
;;  - 물리적으로 연결된 섬(Mark Net 기준)마다 MxTXT 라벨을
;;    최상위 metal 라벨 하나만 남기고 나머지 삭제
;;  - virtual connect로 끊긴 같은 이름의 섬은 섬별로 하나씩 남음
;;
;; 사용법 (layout 창을 현재 창으로 두고 실행):
;;   ts_TxtDelByConn()                 ; dry-run: 삭제 대상만 선택해서 보여줌
;;   ts_TxtDelByConn(?dryRun nil)      ; 실제 삭제
;;   ts_TxtDelByConn(?tmpLib "myTmp")  ; 임시 셀뷰를 만들 라이브러리 지정
;;
;; 안전 설계:
;;  - 라벨 하나 처리 중 에러가 나도 [ERROR]만 찍고 다음으로 진행
;;  - 에러 난 라벨은 지우지 않음 (애매하면 남기는 쪽)
;;
;; ※ SKILL은 호출 시점에 함수를 찾으므로, 파일 전체를 load한 뒤
;;   실행하면 메인이 유틸보다 위에 있어도 문제없음
;;=====================================================================

;;---------------------------------------------------------------------
;; 메인
;;---------------------------------------------------------------------
procedure(ts_TxtDelByConn(@key (dryRun t) (tmpLib "tmpLib"))
  let((cv tmpCv (tmpCell "_markTmp") labels done grp best names
       ok delList (nIsland 0) (nShort 0) (nErr 0) (nDone 0)
       nLbl nIsl nSht nDel)

    ;; ---------- 실행 전 점검 ----------
    cv = geGetEditCellView()
    unless(cv
      error("ts_TxtDelByConn: 편집 중인 layout 셀뷰가 없습니다"))
    unless(isCallable('leMarkNet) && isCallable('leSaveMarkNet)
      error("ts_TxtDelByConn: 이 Virtuoso 버전에는 leMarkNet/leSaveMarkNet이 없습니다"))
    unless(ddGetObj(tmpLib)
      error("ts_TxtDelByConn: %s 라이브러리가 없습니다" tmpLib))
    when(!dryRun && cv~>mode == "r"
      error("ts_TxtDelByConn: 읽기 전용 셀뷰입니다. 편집 모드로 열고 다시 실행하세요"))

    ;; MxTXT layer의 라벨만 대상
    labels = setof(l cv~>shapes
               l~>objType == "label" && rexMatchp("^M[1-5]TXT$" l~>layerName))
    unless(labels
      printf("ts_TxtDelByConn: M1TXT~M5TXT 라벨이 없습니다\n"))

    done = makeTable("done" nil)

    ;; net 이름별 통계 테이블 (기본값 0)
    nLbl = makeTable("nLbl" 0)    ; 라벨 개수
    nIsl = makeTable("nIsl" 0)    ; 섬 개수
    nSht = makeTable("nSht" 0)    ; SHORT 개수
    nDel = makeTable("nDel" 0)    ; 삭제 대상 개수

    foreach(l labels
      nLbl[l~>theLabel] = nLbl[l~>theLabel] + 1)

    ;; ---------- 섬 단위 처리 ----------
    unwindProtect(
      foreach(seed labels
        unless(done[seed]
          nIsland++
          grp = nil
          when(tmpCv errset(dbClose(tmpCv)) tmpCv = nil)

          ;; 1~3. Mark Net -> 임시 셀 저장 -> 섬에 속한 라벨 모으기
          ;;      (이 안에서 에러가 나면 이 섬만 건너뜀)
          ok = errset(
                 progn(
                   ts_UnmarkAll()
                   ts_DeleteCell(tmpLib tmpCell)
                   ts_MarkAt(seed)
                   ts_SaveMark(tmpLib tmpCell seed~>xy)
                   ts_UnmarkAll()
                   tmpCv = dbOpenCellViewByType(tmpLib tmpCell "layout" nil "r")
                   when(tmpCv
                     grp = setof(l labels !done[l] && ts_InIsland(tmpCv l))
                     dbClose(tmpCv)
                     tmpCv = nil)
                   t)
                 t)

          unless(ok
            nErr++
            grp = nil
            printf("[ERROR] %s @ %L 처리 중 에러 - 이 라벨은 지우지 않고 건너뜀\n"
                   seed~>theLabel seed~>xy))

          unless(memq(seed grp) grp = cons(seed grp))   ; 떠 있는 라벨/에러 대비
          foreach(l grp done[l] = t)

          ;; 이 섬에 있는 net 이름들 (중복 제거) -> 이름별 섬 개수
          names = makeTable("names" nil)
          foreach(l grp names[l~>theLabel] = t)
          foreach(n names nIsl[n] = nIsl[n] + 1)

          ;; 4. 하나만 남기고 나머지는 삭제 대상
          when(length(grp) > 1
            if(!forall(l grp l~>theLabel == car(grp)~>theLabel) then
              nShort++
              foreach(n names nSht[n] = nSht[n] + 1)
              printf("[SHORT?] %L @ %L\n" grp~>theLabel seed~>xy)
            else
              ;; 남길 라벨: 최상위 layer -> 맨 왼쪽 -> 맨 위
              best = car(grp)
              foreach(l cdr(grp)
                when(cond(
                       ((l~>layerName != best~>layerName)     ; 1. 상위 layer
                        alphalessp(best~>layerName l~>layerName))
                       ((xCoord(l~>xy) != xCoord(best~>xy))   ; 2. 더 왼쪽
                        xCoord(l~>xy) < xCoord(best~>xy))
                       (t                                     ; 3. 더 위
                        yCoord(l~>xy) > yCoord(best~>xy)))
                  best = l))
              delList = append(delList remove(best grp))))))

      ;; cleanup: 중간에 멈춰도 마킹 해제, 임시 셀뷰 닫기
      progn(
        ts_UnmarkAll()
        when(tmpCv errset(dbClose(tmpCv)))))

    ;; ---------- 결과 출력 ----------
    foreach(l delList
      nDel[l~>theLabel] = nDel[l~>theLabel] + 1)

    foreach(n sort(nLbl->? 'alphalessp)
      printf("[%s] 라벨 %d개 / 섬 %d개 / SHORT %d개 / 삭제 대상 %d개\n"
             n nLbl[n] nIsl[n] nSht[n] nDel[n]))
    printf("[전체] 라벨 %d개 / 섬 %d개 / SHORT %d개 / 삭제 대상 %d개 / 에러 %d개\n"
           length(labels) nIsland nShort length(delList) nErr)

    if(dryRun then
      geDeselectAll()
      foreach(l delList geSelectFig(l))
      printf("dry-run: 삭제 대상을 선택해 두었습니다. 삭제하려면 ?dryRun nil\n")
     else
      foreach(l delList
        when(errset(dbDeleteObject(l)) nDone++))
      printf("%d개 삭제 완료\n" nDone))

    delList))

;;---------------------------------------------------------------------
;; 유틸
;;---------------------------------------------------------------------
;; 라벨이 tmpCv의 같은 metal shape 위에 있는지 (purpose 무관)
procedure(ts_InIsland(tmpCv lbl)
  let((metal pt)
    metal = substring(lbl~>layerName 1 2)          ; "M3TXT" -> "M3"
    pt    = lbl~>xy
    dbGetTrueOverlaps(tmpCv list(pt pt) list(metal))))

;; Mark Net 시작 (버전에 따라 인자가 안 맞으면 단순한 형태로 재시도)
procedure(ts_MarkAt(lbl)
  let((pt lpp)
    pt  = lbl~>xy
    lpp = list(substring(lbl~>layerName 1 2) "drawing")
    cond(
      (errset(leMarkNet(pt ?startLpp lpp ?startLevel 0 ?stopLevel 32)) t)
      (errset(leMarkNet(pt ?stopLevel 32)) t)
      (t leMarkNet(pt)))))     ; 이것도 실패하면 호출한 쪽 errset이 처리

;; 마킹된 net 저장 (?pt / ?point 버전 차이 대비)
procedure(ts_SaveMark(lib cell pt)
  cond(
    (errset(leSaveMarkNet(cell ?libName lib ?viewName "layout" ?pt pt)) t)
    (errset(leSaveMarkNet(cell ?libName lib ?viewName "layout" ?point pt)) t)
    (t leSaveMarkNet(cell ?libName lib ?viewName "layout"))))
    ;; 매번 마킹 해제 후 한 net만 마킹하므로, 점 지정 없이 저장해도 결과 같음

;; 이전 임시 셀 삭제 (없으면 t, 지웠으면 t, 못 지우면 nil)
procedure(ts_DeleteCell(lib cell)
  let((obj)
    obj = ddGetObj(lib cell)
    if(obj then
      car(errset(ddDeleteObj(obj)))
     else
      t)))

;; Mark Net 하이라이트 전체 해제 (에러 나도 무시)
procedure(ts_UnmarkAll()
  cond(
    (isCallable('leUnmarkNet)      errset(leUnmarkNet()))
    (isCallable('leHiUnmarkNetAll) errset(leHiUnmarkNetAll()))
    (t nil)))
