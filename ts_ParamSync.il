;; =====================================================================
;; ts_ParamSync.il
;;
;; 기준 instance와 keyParams(기본 W L NF) 값이 모두 같은 대상만
;; cdfSyncInstParamValue(기준 대상)로 CDF 파라미터 전체를 한 번에 복사.
;; keyParams가 하나라도 다르면 [SKIP] (건드리지 않음).
;;
;; 사용법
;;   1) 기준 instance 1개 선택 -> ts_ParamRef()
;;   2) 대상 instance 선택     -> ts_ParamSync()             ; dry-run (기본)
;;                                ts_ParamSync(?dryRun nil)  ; 실제 적용
;;   옵션: ts_ParamSync(?keyParams '("W" "L" "NF" "M"))
;;
;; 주의
;;   - 기준은 instance 객체로 저장됨. 기준을 지우거나 다른 셀뷰로 가면
;;     ts_ParamRef()를 다시 실행할 것.
;;   - keyParams 비교는 CDF 값(default 포함), 이름 대소문자 무시.
;;     값은 equal로 비교하므로 "1u"와 "1.0u"처럼 표기가 다르면 SKIP.
;;   - libName/cellName이 기준과 다른 instance는 건드리지 않음.
;; =====================================================================

unless( boundp('tsParamRefInst) tsParamRefInst = nil )

;; ---------------------------------------------------------------------
;; 메인 1: 기준 instance 저장
;; ---------------------------------------------------------------------
procedure( ts_ParamRef( @key (keyParams '("W" "L" "NF")) )
  let( (cv insts ref keys)
    cv = ts_ParamCheckEnv(nil)
    when( cv
      insts = setof( o geGetSelSet() o~>objType == "inst" )
      cond(
        ( length(insts) != 1
          printf("[ERROR] 기준 instance를 1개만 선택하세요 (현재 %d개)\n" length(insts)) )
        ( !cdfGetInstCDF(car(insts))
          printf("[ERROR] %s: CDF 없음\n" car(insts)~>name) )
        ( t
          ref = car(insts)
          tsParamRefInst = ref
          keys = ts_ParamKeyVals( ref mapcar('upperCase keyParams) )
          printf("[REF] %s (%s/%s)\n" ref~>name ref~>libName ref~>cellName)
          foreach( k keys
            if( nth(1 k) then
              printf("    %s = %L\n" nth(0 k) nth(2 k))
            else
              printf("    %s = (CDF에 없음, 비교 생략)\n" nth(0 k))
            )
          )
        )
      )
    )
    t
  )
)

;; ---------------------------------------------------------------------
;; 메인 2: 조건 맞는 대상에 기준 파라미터 sync
;; ---------------------------------------------------------------------
procedure( ts_ParamSync( @key (dryRun t) (keyParams '("W" "L" "NF")) )
  let( (cv win ref refOk keyUp refKeys refLib refCell insts instName ok
        tKeys tk reasons i res showList
        (nSel 0) (nOther 0) (nKeyDiff 0) (nSync 0) (nErr 0))

    cv = ts_ParamCheckEnv(!dryRun)
    ref = tsParamRefInst
    ;; 기준 유효성: 지워졌거나 다른 셀뷰면 중단
    refOk = when( cv && ref
      car( errset( ref~>objType == "inst" && eq(ref~>cellView cv) ) )
    )
    cond(
      ( !cv nil )
      ( !ref
        printf("[ERROR] 기준 없음. 먼저 기준 instance 선택 후 ts_ParamRef() 실행\n") )
      ( !refOk
        printf("[ERROR] 기준 instance가 없거나 현재 셀뷰가 아님. ts_ParamRef() 다시 실행\n") )
      ( t
        win     = hiGetCurrentWindow()
        keyUp   = mapcar( 'upperCase keyParams )
        refKeys = ts_ParamKeyVals( ref keyUp )
        refLib  = ref~>libName
        refCell = ref~>cellName
        insts   = setof( o geGetSelSet() o~>objType == "inst" && !eq(o ref) )
        nSel    = length(insts)

        printf("\n===== ts_ParamSync [%s] 기준 %s (%s/%s) / 비교 %L =====\n"
          if(dryRun "DRY-RUN" "APPLY") ref~>name refLib refCell keyParams)

        foreach( inst insts
          instName = inst~>name
          ok = errset(
            if( inst~>libName != refLib || inst~>cellName != refCell then
              nOther = nOther + 1
              printf("[SKIP] %s: 다른 master (%s/%s)\n" instName inst~>libName inst~>cellName)
            else
              ;; keyParams 비교
              tKeys = ts_ParamKeyVals( inst keyUp )
              reasons = nil
              i = 0
              foreach( rk refKeys
                tk = nth(i tKeys)
                unless( equal( cdr(rk) cdr(tk) )
                  reasons = cons( sprintf(nil "%s %L/%L" nth(0 rk) nth(2 rk) nth(2 tk)) reasons )
                )
                i = i + 1
              )

              cond(
                ( reasons
                  nKeyDiff = nKeyDiff + 1
                  printf("[SKIP] %s: 다름 (기준/대상) %L\n" instName reverse(reasons)) )
                ( dryRun
                  nSync = nSync + 1
                  showList = cons(inst showList)
                  printf("[DRY] %s: sync 예정\n" instName) )
                ( t
                  res = cdfSyncInstParamValue( ref inst )
                  if( res then
                    nSync = nSync + 1
                    showList = cons(inst showList)
                    printf("[SYNC] %s\n" instName)
                  else
                    nErr = nErr + 1
                    printf("[ERROR] %s: cdfSyncInstParamValue nil 반환\n" instName)
                  )
                )
              )
            )
            t
          )
          unless( ok
            nErr = nErr + 1
            printf("[ERROR] %L: 처리 실패, 다음으로 진행\n" instName)
          )
        )

        ;; sync 대상만 선택해서 보여주기
        when( win
          errset( geDeselectAll(win) t )
          foreach( inst showList errset( geSelectFig(inst) t ) )
        )

        printf("\n[%s/%s] sync %d개%s / %L 다름 SKIP %d개 / ERROR %d개\n"
          refLib refCell nSync if(dryRun " (예정)" "") keyParams nKeyDiff nErr)
        printf("[전체] 선택 %d개 (기준 제외) / 다른 master SKIP %d개 / ERROR %d개\n"
          nSel nOther nErr)
        when( dryRun
          printf("-> 확인 후 실제 적용: ts_ParamSync(?dryRun nil)\n"))
      )
    )
    t
  )
)

;; ---------------------------------------------------------------------
;; 유틸: instance의 keyParams 값 -> ((KEY found value) ...)
;;       CDF 이름 대소문자 무시, CDF에 없으면 found = nil
;; ---------------------------------------------------------------------
procedure( ts_ParamKeyVals( inst keyUp )
  let( (cdf out found val)
    cdf = cdfGetInstCDF(inst)
    out = nil
    foreach( key keyUp
      found = nil
      val = nil
      when( cdf
        foreach( p cdf~>parameters
          when( !found && upperCase(p~>name) == key
            found = t
            val = p~>value
          )
        )
      )
      out = cons( list(key found val) out )
    )
    reverse(out)
  )
)

;; ---------------------------------------------------------------------
;; 유틸: 실행 전 점검 (함수 존재 / 셀뷰 / 읽기 전용)
;; ---------------------------------------------------------------------
procedure( ts_ParamCheckEnv( needWrite )
  let( (ok res cv)
    ok = t
    foreach( fn '(geGetEditCellView geGetSelSet hiGetCurrentWindow cdfGetInstCDF
                  cdfSyncInstParamValue geSelectFig geDeselectAll upperCase)
      unless( isCallable(fn)
        printf("[ERROR] 함수 없음: %L\n" fn)
        ok = nil
      )
    )
    when( ok
      res = errset( geGetEditCellView() )
      cv = if( res car(res) nil )
      cond(
        ( !cv
          printf("[ERROR] 편집 중인 셀뷰 없음\n")
          ok = nil )
        ( needWrite && cv~>mode == "r"
          printf("[ERROR] %s/%s 읽기 전용. 편집 모드로 연 뒤 실행\n" cv~>libName cv~>cellName)
          ok = nil )
      )
    )
    if( ok cv nil )
  )
)
