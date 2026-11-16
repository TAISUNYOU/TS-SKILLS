;; =====================================================================
;; ts_PwrIsland.il
;;
;; V로 시작하는 net의 MxTXT 라벨에서 출발해 물리적 섬(Mark Net 기준)을
;; 구하고, 섬마다 대표 라벨 1개의 좌표를 출력. (읽기 전용, 셀 수정 없음)
;;
;; 사용법 (layout 창을 현재 창으로 두고 실행):
;;   load("ts_TxtDelByConn.il")   ; 유틸 함수 재사용 (먼저 load 필요)
;;   load("ts_PwrIsland.il")
;;   ts_PwrIsland()
;;   ts_PwrIsland(?tmpLib "myTmp")   ; 임시 셀 만들 라이브러리 지정
;;
;; 재사용 유틸 (ts_TxtDelByConn.il):
;;   ts_MarkAt ts_SaveMark ts_DeleteCell ts_UnmarkAll ts_InIsland
;;
;; 참고
;;   - 라벨 없는 섬은 찾지 않음 (라벨에서만 출발)
;;   - 한 섬에 이름이 다른 V라벨이 섞여 있으면 [SHORT?]로 표시
;;   - 섬 판별 중 에러 난 라벨은 [ERROR] 출력 후 다음으로 진행
;; =====================================================================

;; ---------------------------------------------------------------------
;; 메인
;; ---------------------------------------------------------------------
procedure( ts_PwrIsland( @key (tmpLib "tmpLib") )
  let( (ok res cv labels done lblCnt islCnt tmpCv grp names name
        (tmpCell "_markTmp") (nIsland 0) (nShort 0) (nErr 0))

    ;; ---- 점검 ----
    ok = t
    ;; Cadence 함수는 문서로 확인됨. ts_TxtDelByConn.il 유틸만 점검
    foreach( fn '(ts_MarkAt ts_SaveMark ts_DeleteCell ts_UnmarkAll ts_InIsland)
      unless( isCallable(fn)
        printf("[ERROR] 함수 없음: %L\n" fn)
        ok = nil
      )
    )
    unless( isCallable('ts_InIsland)
      printf("        -> ts_TxtDelByConn.il 을 먼저 load 하세요\n"))
    when( ok
      res = errset( geGetEditCellView() )
      cv = when( res car(res) )
      unless( cv
        printf("[ERROR] 편집 중인 layout 셀뷰 없음\n")
        ok = nil
      )
    )
    when( ok && !ddGetObj(tmpLib)
      printf("[ERROR] %s 라이브러리 없음\n" tmpLib)
      ok = nil
    )

    when( ok
      ;; ---- V로 시작하는 MxTXT 라벨 (이름순) ----
      labels = setof( l cv~>shapes
                 l~>objType == "label"
                 && rexMatchp("^M[1-5]TXT$" l~>layerName)
                 && rexMatchp("^V" l~>theLabel) )
      labels = sort( labels lambda( (a b) alphalessp(a~>theLabel b~>theLabel) ) )

      done   = makeTable("done" nil)
      lblCnt = makeTable("lblCnt" 0)   ; net별 라벨 수
      islCnt = makeTable("islCnt" 0)   ; net별 섬 수
      foreach( l labels lblCnt[l~>theLabel] = lblCnt[l~>theLabel] + 1 )

      printf("\n===== ts_PwrIsland %s/%s / V* 라벨 %d개 =====\n"
        cv~>libName cv~>cellName length(labels))

      ;; ---- 섬 단위 처리 ----
      unwindProtect(
        foreach( seed labels
          unless( done[seed]
            grp = nil
            when( tmpCv errset(dbClose(tmpCv)) tmpCv = nil )

            ok = errset(
                   progn(
                     ts_UnmarkAll()
                     ts_DeleteCell(tmpLib tmpCell)
                     ts_MarkAt(seed)
                     ts_SaveMark(tmpLib tmpCell seed~>xy)
                     ts_UnmarkAll()
                     tmpCv = dbOpenCellViewByType(tmpLib tmpCell "layout" nil "r")
                     when( tmpCv
                       grp = setof( l labels !done[l] && ts_InIsland(tmpCv l) )
                       dbClose(tmpCv)
                       tmpCv = nil
                     )
                     t
                   )
                   t )

            unless( memq(seed grp) grp = cons(seed grp) )
            foreach( l grp done[l] = t )

            if( !ok then
              nErr = nErr + 1
              printf("[ERROR] %s @ %L 섬 판별 실패 - 건너뜀\n" seed~>theLabel seed~>xy)
            else
              name = seed~>theLabel
              nIsland = nIsland + 1
              islCnt[name] = islCnt[name] + 1
              printf("[%s] 섬 #%d : %s @ %L (섬 안 V라벨 %d개)\n"
                name islCnt[name] seed~>layerName seed~>xy length(grp))

              ;; 이름이 다른 V라벨이 섞인 섬
              names = nil
              foreach( l grp
                unless( member(l~>theLabel names) names = cons(l~>theLabel names) )
              )
              when( length(names) > 1
                nShort = nShort + 1
                printf("    [SHORT?] 섬 안 라벨 이름: %L\n" reverse(names))
              )
            )
          )
        )
        ;; cleanup: 중간에 멈춰도 마킹 해제, 임시 셀뷰 닫기
        progn(
          ts_UnmarkAll()
          when( tmpCv errset(dbClose(tmpCv)) )
        )
      )

      ;; ---- 요약 ----
      printf("\n")
      foreach( n sort(lblCnt->? 'alphalessp)
        printf("[%s] 라벨 %d개 / 섬 %d개\n" n lblCnt[n] islCnt[n])
      )
      printf("[전체] net %d개 / 라벨 %d개 / 섬 %d개 / SHORT? %d개 / ERROR %d개\n"
        length(lblCnt->?) length(labels) nIsland nShort nErr)
    )
    t
  )
)
