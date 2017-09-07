CREATE OR REPLACE PACKAGE [������]_[������]_[����/����������]_[{���������}]_PKG IS

  /**
    * @author Reznichenko SV, email: rsv@kibank.ru
    * @version 0.0
    * <hr>
    * ������:          [������]</br>
    * ��������:        [�������� ������]</br>
    * Commit inside:   YES</br>
    * Rollback inside: NO</br>
    * <hr>
    */

  /**
    ������ �������  �� �������
    @param req_id     ������������� �������
    @param req_type   ��� �������
    @param result     ��� ������ �������
    @param errmsg     ����� ������ �������
    @param timeout    ����-��� ���������� �������.
    @param oper_type  ��� ��������
    @param ppp_id     ������������� ���, ��� ����������� ��������
    @param user_id    ������������� ������������, ������������ ��������
    @param agent_id   ������������� ������, ��� ����������� ��������
    @param prv_id     ������������� ���������� �����
    @param service_id ����� ������, �� �������, ����������� ��������
    @param prog_id    ������������� ���� �� �������� ����������� ��������
    @param acc_pu     ���� �������� � ������� ��
    @param summ       ����� ��������
    @param outp       ����� ��������� �������������� ����������
    @param inp        ����� �������� �������������� ����������
  */
  PROCEDURE hook(req_id     IN OUT NUMBER,
                 req_type   IN PLS_INTEGER,
                 RESULT     OUT PLS_INTEGER,
                 errmsg     OUT VARCHAR2,
                 timeout    IN PLS_INTEGER,
                 oper_type  IN VARCHAR2,
                 ppp_id     IN NUMBER,
                 user_id    IN NUMBER,
                 agent_id   IN NUMBER,
                 prv_id     IN NUMBER,
                 service_id IN NUMBER,
                 prog_id    IN NUMBER,
                 acc_pu     IN VARCHAR2,
                 summ       IN OUT NUMBER,
                 outp       IN VARCHAR2,
                 inp        OUT VARCHAR2);
END;
/
CREATE OR REPLACE PACKAGE BODY [������]_[������]_[����/����������]_[{���������}]_PKG IS
  --��� ������.
  c$module CONSTANT VARCHAR2(50) := $$PLSQL_UNIT;

  /** ���� �������� */
  --��� ������� "������ �� ���������� ��������" HOOK BEFORE_PAYM_PROC
  c$rt_req CONSTANT PLS_INTEGER := 1;
  --��� ������� "����������� � ����������� ��������" HOOK AFTER_PAYM_PROC
  c$rt_confirm CONSTANT PLS_INTEGER := 2;
  --��� ������� "������ ������� �� ����������� (�� ��������� ���������� �������)"
  c$rt_undo_req CONSTANT PLS_INTEGER := 3;
  --��� ������� "������ ������� �� ����������� (�� ��������� ���������� �������)"
  c$rt_undo_pay CONSTANT PLS_INTEGER := 4;
  --��� ������� "������" HOOK AFTER_PAYM_PROC
  c$rt_storno CONSTANT PLS_INTEGER := 5;
  --��� ������� "��� �������� �� ��������" HOOK TOQUEUE
  c$rt_toqueue CONSTANT PLS_INTEGER := 6;
  --��� ������� "��� �������� �� ��������(������)" HOOK TOQUEUE
  c$rt_toqueue_storno CONSTANT PLS_INTEGER := 7;

  /** ��������� �������� */
  --��������� ����������
  c$err_ok CONSTANT PLS_INTEGER := 0;
  --����-��� ��� ���������� �������
  c$err_timeout CONSTANT PLS_INTEGER := 1;
  --������ ��������
  c$err_denied CONSTANT PLS_INTEGER := 2;
  --��������� ������ ��� ���������� �������
  c$err_syserr CONSTANT PLS_INTEGER := 4;
  --�������������� ���������� ������ ��� ���������� �������
  c$err_apperr CONSTANT PLS_INTEGER := 5;
  --������������ ���������� ������ ��� ���������� �������
  c$err_appexc CONSTANT PLS_INTEGER := 1001;
  --��������� "������ �� �������"
  c$state_cl_req CONSTANT PLS_INTEGER := -1;
  --��������� "������ ������� �� �������"
  c$state_cl_undo CONSTANT PLS_INTEGER := -2;
  --��������� "������ ��������� ����������"
  c$state_lr_ans CONSTANT PLS_INTEGER := 1;
  --��������� "������ ������� ���������� ����������"
  c$state_lr_undo CONSTANT PLS_INTEGER := 2;
  --�������� ����������
  c$ok CONSTANT PLS_INTEGER := 1;
  --��������� � �������
  c$err CONSTANT PLS_INTEGER := 0;

  /**
  * ��� ��� ������ ������� �� ����������� ���������� <br>
  *    req_id     ������������� �������<br>
  *    req_type   ��� �������<br>
  *    RESULT     ��� ������ �������<br>
  *    errmsg     ����� ������ �������<br>
  *    timeout    ����-��� ���������� �������<br>
  *    oper_type  ��� ��������<br>
  *    ppp_id     ������������� ���, ��� ����������� ��������<br>
  *    user_id    ������������� ������������, ������������ ��������<br>
  *    agent_id   ������������� ������, ��� ����������� ��������<br>
  *    prv$id     ������������� ���������� �����<br>
  *    service_id ����� ������, �� �������, ����������� ��������<br>
  *    prog_id    ������������� ���� �� �������� ����������� ��������<br>
  *    acc_pu     ���� �������� � ������� ��<br>
  *    summ       ����� ��������<br>
  *    outp       ����� ��������� �������������� ����������<br>
  *    inp        ����� �������� �������������� ����������<br>
  */
  TYPE t_req_prm IS RECORD(
    req_id     NUMBER,
    req_type   PLS_INTEGER,
    RESULT     PLS_INTEGER,
    errmsg     VARCHAR2(4000),
    timeout    PLS_INTEGER,
    oper_type  PLS_INTEGER,
    ppp_id     NUMBER,
    user_id    NUMBER,
    agent_id   NUMBER,
    prv_id     NUMBER,
    service_id NUMBER,
    prog_id    NUMBER,
    acc_pu     VARCHAR2(200),
    summ       NUMBER,
    outp       VARCHAR2(4000),
    inp        VARCHAR2(4000));

  /**
  * ��� ������ <br>
  *    code      ��� ������<br>
  *    actor     ��� ������<br>
  *    expected  ����������������� ������ ��� ���<br>
  *    msg       �����<br>
  *    commonmsg �������� �����<br>
  *    stack     sql ����(sql ����� ������)<br>
  */
  TYPE t_fault IS RECORD(
    code      VARCHAR2(512),
    actor     VARCHAR2(256),
    expected  BOOLEAN,
    msg       VARCHAR2(2000),
    commonmsg VARCHAR2(2000),
    stack     VARCHAR2(4000));

  --������ ������
  g$err t_fault;

  --������ ����������� ������������
  unique_constraint EXCEPTION;
  PRAGMA EXCEPTION_INIT(unique_constraint, -00001);
  --������ signature of package ... has been changed
  tstamp EXCEPTION;
  PRAGMA EXCEPTION_INIT(tstamp, -04062);
  --������ ��������������������� ������
  not_init EXCEPTION;
  PRAGMA EXCEPTION_INIT(not_init, -06531);
  --������ ��������.
  hook_err EXCEPTION;

  /**
  * �������������� ������ � ��� ����������
  * @param p$req    ������ �� ������� ��������
  * @param p$result ��� ����������
  * @param p$errmsg ����� ��������� �� ������
  */
  PROCEDURE define$appcode(p$req    IN OUT reqs%ROWTYPE,
                           p$result IN PLS_INTEGER DEFAULT NULL,
                           p$errmsg IN VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF p$result IS NOT NULL
    THEN
      p$req.result := p$result;
      p$req.errmsg := p$errmsg;
    ELSE
      IF g$err.code IS NULL
      THEN
        p$req.result := c$err_ok;
        p$req.errmsg := NULL;
      ELSE
        p$req.result := c$err_appexc;
        p$req.errmsg := g$err.msg;
      END IF;
    END IF;
  END;

  /**
  * ���������/����������� � ������� ��������
  * @param p$req ������ �� ������� ��������
  */
  PROCEDURE save$req(p$req IN OUT reqs%ROWTYPE) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    --�������� ������� ������ �� uno � ������� req_id
    BEGIN
      SELECT r.req_id
        INTO p$req.req_id
        FROM reqs r
       WHERE r.uno = p$req.uno;
    EXCEPTION
      WHEN no_data_found THEN
        NULL;
    END;
  
    --���� id ������� ������ ������� ������
    IF p$req.req_id IS NULL
    THEN
      SELECT reqs_seq.nextval INTO p$req.req_id FROM dual;
      INSERT INTO reqs VALUES p$req;
    ELSE
      IF p$req.req_type = c$rt_storno
      THEN
        UPDATE reqs r
           SET r.undo_stamp = p$req.undo_stamp,
               r.req_state  = p$req.req_state,
               r.req_type   = p$req.req_type,
               r.result     = p$req.result,
               r.errmsg     = p$req.errmsg
         WHERE r.req_id = p$req.req_id;
      ELSIF p$req.req_type IN (c$rt_req, c$rt_confirm)
      THEN
        UPDATE reqs r
           SET r.ans_stamp = p$req.ans_stamp,
               r.req_state = p$req.req_state,
               r.req_type  = p$req.req_type,
               r.uno       = p$req.uno,
               r.result    = p$req.result,
               r.errmsg    = p$req.errmsg,
               r.inp       = p$req.inp
         WHERE r.req_id = p$req.req_id;
      END IF;
    END IF;
  
    COMMIT;
  END;

  /**
  * ��������� ���
  * @param p$req ������ �� ������� ��������
  */
  PROCEDURE save$log(p$req IN reqs%ROWTYPE) IS
    v$type_log VARCHAR2(50);
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    IF NOT g$err.expected
    THEN
      v$type_log := 'ERR';
    ELSE
      v$type_log := 'MSG';
    END IF;
  
    online_pl.add_msglog(type_     => v$type_log,
                         module_   => c$module,
                         subject_  => NVL(g$err.commonmsg, g$err.msg),
                         text_     => 'req_id: ' || p$req.req_id || CHR(10) ||
                                      'code  : ' || g$err.code || CHR(10) ||
                                      'actor : ' || g$err.actor || CHR(10),
                         sql_text_ => g$err.stack,
                         uno_      => p$req.uno);
  END;

  /**
  * ��������� ������ ���������� �� ������
  * @param p$array ������ ����������
  * @param p$str ������ ����������
  */
  PROCEDURE set$param_array(p$array IN OUT param_array,
                            p$str   IN VARCHAR2) IS
    CURSOR param(p$str IN xmltype) IS
      --NoFormat Start
        SELECT e.name,
               e.val
          FROM dual,
               XMLTABLE('req/e'
                 PASSING p$str
                 COLUMNS "Seqno" FOR ordinality,
                         NAME VARCHAR2(1000) path './@a',
                         val VARCHAR2(1000) path '.') e;
      --NoFormat End
    v$xmlstr xmltype;
  BEGIN
    IF p$str IS NOT NULL
    THEN
      v$xmlstr := xmltype(REGEXP_REPLACE(REGEXP_REPLACE(p$str,
                                                        '[^[/[:alnum:][:punct:] ]]*'),
                                         'req>',
                                         'req>',
                                         1,
                                         0,
                                         'i'));
      FOR c IN param(v$xmlstr)
      LOOP
        p$array.add$val(c.name, c.val);
      END LOOP;
    END IF;
  END;

  /**
  * ������ ������ ������
  */
  PROCEDURE clear$err IS
  BEGIN
    g$err.code      := NULL;
    g$err.actor     := NULL;
    g$err.expected  := NULL;
    g$err.msg       := NULL;
    g$err.commonmsg := NULL;
    g$err.stack     := NULL;
  END;

  /**
  * ������������� ������ �� p$code, � ������ �������� p$subcode ���������� g$err.code = p$subcode
  * @param p$actor      ��� ������
  * @param p$code       ��� ������
  * @param p$subcode    ��� ��� ������
  * @param p$msg        ����� ���������
  * @param p$common_msg ����� ����� ������
  * @param p$param1     ��������1 � �������
  * @param p$value1     �������� ���������1
  * @param p$param2     ��������2 � �������
  * @param p$value2     �������� ���������2
  * @param p$param3     ��������3 � �������
  * @param p$value3     �������� ���������3
  * @param p$param4     ��������4 � �������
  * @param p$value4     �������� ���������4
  * @param p$param5     ��������5 � �������
  * @param p$value5     �������� ���������5
  * @param p$expected   ����������������� ������ ��� ���
  * @param p$stack      sql ����� ������
  */
  PROCEDURE raise$err(p$actor      VARCHAR2,
                      p$code       NUMBER,
                      p$subcode    NUMBER := NULL,
                      p$msg        VARCHAR2 := NULL,
                      p$common_msg VARCHAR2 := NULL,
                      p$param1     VARCHAR2 := NULL,
                      p$value1     VARCHAR2 := NULL,
                      p$param2     VARCHAR2 := NULL,
                      p$value2     VARCHAR2 := NULL,
                      p$param3     VARCHAR2 := NULL,
                      p$value3     VARCHAR2 := NULL,
                      p$param4     VARCHAR2 := NULL,
                      p$value4     VARCHAR2 := NULL,
                      p$param5     VARCHAR2 := NULL,
                      p$value5     VARCHAR2 := NULL,
                      p$expected   BOOLEAN := FALSE,
                      p$raise      BOOLEAN := TRUE,
                      p$stack      VARCHAR2 := NULL) IS
    v$msg VARCHAR2(4000);
  BEGIN
    IF p$msg IS NULL
    THEN
      v$msg := kp.pk_msg.msg(ppfx    => p$actor,
                             pcode   => p$code,
                             pparam1 => p$param1,
                             pvalue1 => p$value1,
                             pparam2 => p$param2,
                             pvalue2 => p$value2,
                             pparam3 => p$param3,
                             pvalue3 => p$value3,
                             pparam4 => p$param4,
                             pvalue4 => p$value4,
                             pparam5 => p$param5,
                             pvalue5 => p$value5);
    ELSE
      v$msg := p$msg;
    END IF;
  
    g$err           := NULL;
    g$err.actor     := p$actor;
    g$err.code      := NVL(p$subcode, p$code);
    g$err.msg       := v$msg;
    g$err.commonmsg := p$common_msg;
    g$err.expected  := p$expected;
  
    IF p$stack IS NOT NULL
    THEN
      g$err.stack := p$stack || CHR(10);
    END IF;
  
    IF NOT p$expected
    THEN
      -- ��� ������������������� ������ ������� ����
      g$err.commonmsg := c$module || ' ora_error';
      g$err.stack     := g$err.stack || dbms_utility.format_error_stack ||
                         dbms_utility.format_error_backtrace();
    END IF;
  
    IF p$raise
    THEN
      RAISE hook_err;
    END IF;
  END;

  /**
  * �������� ��� ��������� �������������� �������� ��-���������
  * @param p$srvnum ��� ������
  * 
  * @return ������
  */
  FUNCTION get$acc_pu_name(p$srvnum IN NUMBER) RETURN VARCHAR2 IS
    v$name VARCHAR2(100);
  BEGIN
    SELECT f.shortname
      INTO v$name
      FROM kp.apx$params p,
           kp.apx$fields f,
           kp.services   s
     WHERE 1 = 1
           AND p.apxfield = f.id
           AND s.apxtype_out = f.apxtype
           AND s.num = p$srvnum
           AND upper(p.name) = 'ABONENT'
           AND upper(p.value) = 'ACCOUNT'
           AND rownum = 1
     ORDER BY f.num,
              p.name;
  
    RETURN v$name;
  EXCEPTION
    WHEN no_data_found THEN
      RETURN NULL;
  END;

  /**
  * �������� ����������� �������
  * @param p$req ������ �������
  * @param p$outp ������ �������� ����������
  * @param p$inp  ������ ��������� ����������
  */
  PROCEDURE req$check(p$req  IN OUT reqs%ROWTYPE,
                      p$outp IN OUT param_array,
                      p$inp  IN OUT param_array) IS
    v$cnt_okato NUMBER;
  BEGIN
    NULL;
  EXCEPTION
    WHEN hook_err THEN
      NULL;
  END;

  /**
  * ������������� �������
  * @param p$req ������ �������
  * @param p$outp ������ �������� ����������
  * @param p$inp  ������ ��������� ����������
  */
  PROCEDURE req$confirm(p$req  IN OUT reqs%ROWTYPE,
                        p$outp IN OUT param_array,
                        p$inp  IN OUT param_array) IS
  BEGIN
    NULL;
  EXCEPTION
    WHEN hook_err THEN
      NULL;
  END;

  /**
  * ������ �������
  * @param p$req ������ �������
  * @param p$outp ������ �������� ����������
  * @param p$inp  ������ ��������� ����������
  */
  PROCEDURE req$storno(p$req  IN OUT reqs%ROWTYPE,
                       p$outp IN OUT param_array,
                       p$inp  IN OUT param_array) IS
  BEGIN
    NULL;
  EXCEPTION
    WHEN hook_err THEN
      NULL;
  END;

  /**
  * ������ �������  �� �������
  * @param req_id     ������������� �������
  * @param req_type   ��� �������
  * @param result     ��� ������ �������
  * @param errmsg     ����� ������ �������
  * @param timeout    ����-��� ���������� �������.
  * @param oper_type  ��� ��������
  * @param ppp_id     ������������� ���, ��� ����������� ��������
  * @param user_id    ������������� ������������, ������������ ��������
  * @param agent_id   ������������� ������, ��� ����������� ��������
  * @param prv_id     ������������� ���������� �����
  * @param service_id ����� ������, �� �������, ����������� ��������
  * @param prog_id    ������������� ���� �� �������� ����������� ��������
  * @param acc_pu     ���� �������� � ������� ��
  * @param summ       ����� ��������
  * @param outp       ����� ��������� �������������� ����������
  * @param inp        ����� �������� �������������� ����������
  */
  PROCEDURE hook(req_id     IN OUT NUMBER,
                 req_type   IN PLS_INTEGER,
                 RESULT     OUT PLS_INTEGER,
                 errmsg     OUT VARCHAR2,
                 timeout    IN PLS_INTEGER,
                 oper_type  IN VARCHAR2,
                 ppp_id     IN NUMBER,
                 user_id    IN NUMBER,
                 agent_id   IN NUMBER,
                 prv_id     IN NUMBER,
                 service_id IN NUMBER,
                 prog_id    IN NUMBER,
                 acc_pu     IN VARCHAR2,
                 summ       IN OUT NUMBER,
                 outp       IN VARCHAR2,
                 inp        OUT VARCHAR2) IS
    -- C�������� ������ �������
    v$req reqs%ROWTYPE;
  
    -- ������ �������� ����������
    v$outp param_array := param_array();
  
    -- ������ ��������� ����������
    v$inp param_array := param_array();
  
    -- ������������ �������������� ��������
    v$acc_pu_name VARCHAR2(100);
  BEGIN
    clear$err;
  
    v$req.req_date  := SYSDATE;
    v$req.req_stamp := dbms_utility.get_time;
    v$req.req_type  := req_type;
    v$req.result    := RESULT;
    v$req.errmsg    := errmsg;
    v$req.oper_type := oper_type;
    v$req.ppp_id    := ppp_id;
    v$req.user_id   := user_id;
    v$req.prog_id   := prog_id;
    v$req.agent_id  := agent_id;
    v$req.prv_id    := prv_id;
    v$req.srvnum    := service_id;
    v$req.acc_pu    := acc_pu;
    v$req.summ      := summ;
    v$req.outp      := outp;
    v$req.inp       := inp;
    v$req.req_state := c$state_cl_req;
  
    set$param_array(v$outp, outp);
  
    IF v$req.req_type IN (c$rt_storno, c$rt_toqueue_storno)
    THEN
      v$req.uno := to_number(v$outp.get$val('UNOP'));
    ELSE
      v$req.uno := to_number(v$outp.get$val('UNO'));
    END IF;
  
    -- ������� ������������� �������� �� ���������
    v$acc_pu_name := get$acc_pu_name(v$req.srvnum);
    IF v$acc_pu_name IS NOT NULL AND v$req.acc_pu IS NULL
    THEN
      v$req.acc_pu := v$outp.get$val(v$acc_pu_name);
    END IF;
  
    -- �������� ������
    save$req(v$req);
  
    -- ��������
    IF v$req.req_type = c$rt_req
    THEN
      req$check(v$req, v$outp, v$inp);
    
      v$req.req_state := NULL;
      v$req.ans_stamp := dbms_utility.get_time;
      define$appcode(v$req);
      -- ������������� �������
    ELSIF v$req.req_type = c$rt_confirm
    THEN
      req$confirm(v$req, v$outp, v$inp);
    
      v$req.req_state := NULL;
      v$req.ans_stamp := dbms_utility.get_time;
    
      define$appcode(v$req);
      -- ������ �������
    ELSIF v$req.req_type = c$rt_storno
    THEN
      req$storno(v$req, v$outp, v$inp);
    
      v$req.req_state  := NULL;
      v$req.undo_stamp := dbms_utility.get_time;
    
      define$appcode(v$req);
      -- ������ ��������
    ELSIF v$req.req_type IN (c$rt_undo_req, c$rt_undo_pay)
    THEN
      define$appcode(v$req);
      -- ��� �������� �� ��������, ��������(������)
    ELSIF v$req.req_type IN (c$rt_toqueue, c$rt_toqueue_storno)
    THEN
      define$appcode(v$req);
    END IF;
  
    BEGIN
      IF v$inp.param.count > 0
      THEN
        v$req.inp := v$inp.toxml().getstringval();
      END IF;
    EXCEPTION
      WHEN not_init THEN
        NULL;
    END;
  
    -- ��������� ������
    save$req(v$req);
  
    /** �������� ��������� ���������� */
    req_id := v$req.req_id;
    RESULT := v$req.result;
    errmsg := v$req.errmsg;
    summ   := v$req.summ;
    inp    := v$req.inp;
  EXCEPTION
    WHEN OTHERS THEN
      raise$err(p$actor => 'KIB.HOOK', p$code => 0, p$raise => FALSE);
      define$appcode(v$req);
      save$log(v$req);
      req_id := v$req.req_id;
      RESULT := v$req.result;
      errmsg := v$req.errmsg;
  END;

BEGIN
  EXECUTE IMMEDIATE 'ALTER SESSION SET NLS_NUMERIC_CHARACTERS=''.,''';

END;
/
