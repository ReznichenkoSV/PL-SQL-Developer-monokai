CREATE OR REPLACE PACKAGE [Модуль]_[группа]_[цель/назначение]_[{подгруппа}]_PKG IS

  /**
    * @author Reznichenko SV, email: rsv@kibank.ru
    * @version 0.0
    * <hr>
    * Проект:          [Проект]</br>
    * Описание:        [Описание модуля]</br>
    * Commit inside:   YES</br>
    * Rollback inside: NO</br>
    * <hr>
    */

  /**
    Запрос ловушки  от клиента
    @param req_id     идентификатор запроса
    @param req_type   тип запроса
    @param result     код ошибки запроса
    @param errmsg     текст ошибки запроса
    @param timeout    тайм-аут выполнения ловушки.
    @param oper_type  тип операции
    @param ppp_id     идентификатор ППП, где совершается операция
    @param user_id    идентификатор пользователя, совершающего операцию
    @param agent_id   идентификатор агента, где совершается операция
    @param prv_id     идентификатор поставщика услуг
    @param service_id номер услуги, по которой, совершается операция
    @param prog_id    идентификатор АРМа из которого выполняется операция
    @param acc_pu     счет абонента в системе ПУ
    @param summ       сумма операции
    @param outp       текст исходящих дополнительных параметров
    @param inp        текст входящих дополнительных параметров
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
CREATE OR REPLACE PACKAGE BODY [Модуль]_[группа]_[цель/назначение]_[{подгруппа}]_PKG IS
  --Имя модуля.
  c$module CONSTANT VARCHAR2(50) := $$PLSQL_UNIT;

  /** Типы запросов */
  --Тип запроса "Запрос на выполнение операции" HOOK BEFORE_PAYM_PROC
  c$rt_req CONSTANT PLS_INTEGER := 1;
  --Тип запроса "Уведомление о проведенной операции" HOOK AFTER_PAYM_PROC
  c$rt_confirm CONSTANT PLS_INTEGER := 2;
  --Тип запроса "Отмена запроса до авторизации (до окончания выполнения ловушки)"
  c$rt_undo_req CONSTANT PLS_INTEGER := 3;
  --Тип запроса "Отмена запроса до авторизации (до окончания выполнения ловушки)"
  c$rt_undo_pay CONSTANT PLS_INTEGER := 4;
  --Тип запроса "Сторно" HOOK AFTER_PAYM_PROC
  c$rt_storno CONSTANT PLS_INTEGER := 5;
  --Тип запроса "При отправке на проводку" HOOK TOQUEUE
  c$rt_toqueue CONSTANT PLS_INTEGER := 6;
  --Тип запроса "При отправке на проводку(сторно)" HOOK TOQUEUE
  c$rt_toqueue_storno CONSTANT PLS_INTEGER := 7;

  /** Состояния запросов */
  --Нормально завершение
  c$err_ok CONSTANT PLS_INTEGER := 0;
  --Тайм-аут при выполнении ловушки
  c$err_timeout CONSTANT PLS_INTEGER := 1;
  --Доступ запрещен
  c$err_denied CONSTANT PLS_INTEGER := 2;
  --Системная ошибка при выполнении ловушки
  c$err_syserr CONSTANT PLS_INTEGER := 4;
  --Неопределенная прикладная ошибка при выполнении ловушки
  c$err_apperr CONSTANT PLS_INTEGER := 5;
  --Определенная прикладная ошибка при выполнении ловушки
  c$err_appexc CONSTANT PLS_INTEGER := 1001;
  --Состояние "Запрос от клиента"
  c$state_cl_req CONSTANT PLS_INTEGER := -1;
  --Состояние "Отмена запроса от клиента"
  c$state_cl_undo CONSTANT PLS_INTEGER := -2;
  --Состояние "Запрос обработан листенером"
  c$state_lr_ans CONSTANT PLS_INTEGER := 1;
  --Состояние "Отмена запроса обработана листенером"
  c$state_lr_undo CONSTANT PLS_INTEGER := 2;
  --Успешное завершение
  c$ok CONSTANT PLS_INTEGER := 1;
  --Завершено с ошибкой
  c$err CONSTANT PLS_INTEGER := 0;

  /**
  * Тип для вызова ловушки из клиентского приложения <br>
  *    req_id     идентификатор запроса<br>
  *    req_type   тип запроса<br>
  *    RESULT     код ошибки запроса<br>
  *    errmsg     текст ошибки запроса<br>
  *    timeout    тайм-аут выполнения ловушки<br>
  *    oper_type  тип операции<br>
  *    ppp_id     идентификатор ППП, где совершается операция<br>
  *    user_id    идентификатор пользователя, совершающего операцию<br>
  *    agent_id   идентификатор агента, где совершается операция<br>
  *    prv$id     идентификатор поставщика услуг<br>
  *    service_id номер услуги, по которой, совершается операция<br>
  *    prog_id    идентификатор АРМа из которого выполняется операция<br>
  *    acc_pu     счет абонента в системе ПУ<br>
  *    summ       сумма операции<br>
  *    outp       текст исходящих дополнительных параметров<br>
  *    inp        текст входящих дополнительных параметров<br>
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
  * Тип ошибка <br>
  *    code      код ошибки<br>
  *    actor     имя модуля<br>
  *    expected  документированная ошибка или нет<br>
  *    msg       текст<br>
  *    commonmsg основной текст<br>
  *    stack     sql стэк(sql текст ошибки)<br>
  */
  TYPE t_fault IS RECORD(
    code      VARCHAR2(512),
    actor     VARCHAR2(256),
    expected  BOOLEAN,
    msg       VARCHAR2(2000),
    commonmsg VARCHAR2(2000),
    stack     VARCHAR2(4000));

  --Массив ошибки
  g$err t_fault;

  --Ошибка ограничения уникальности
  unique_constraint EXCEPTION;
  PRAGMA EXCEPTION_INIT(unique_constraint, -00001);
  --Ошибка signature of package ... has been changed
  tstamp EXCEPTION;
  PRAGMA EXCEPTION_INIT(tstamp, -04062);
  --Ошибка неинициализированного набора
  not_init EXCEPTION;
  PRAGMA EXCEPTION_INIT(not_init, -06531);
  --Ошибка проверки.
  hook_err EXCEPTION;

  /**
  * Переопределить ошибку в код приложения
  * @param p$req    строка из таблицы запросов
  * @param p$result код завершения
  * @param p$errmsg текст сообщения об ошибки
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
  * Сохраняем/редактируем в таблице запросов
  * @param p$req строка из таблицы запросов
  */
  PROCEDURE save$req(p$req IN OUT reqs%ROWTYPE) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    --Проверим наличие записи по uno и получим req_id
    BEGIN
      SELECT r.req_id
        INTO p$req.req_id
        FROM reqs r
       WHERE r.uno = p$req.uno;
    EXCEPTION
      WHEN no_data_found THEN
        NULL;
    END;
  
    --Если id запроса пустой создаем запись
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
  * Сохраняем лог
  * @param p$req строка из таблицы запросов
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
  * Заполняем массив параметров из строки
  * @param p$array массив параметров
  * @param p$str строка параметров
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
  * Чистим массив ошибки
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
  * Сгенерировать ошибку по p$code, в случае указания p$subcode выставляем g$err.code = p$subcode
  * @param p$actor      имя модуля
  * @param p$code       код ошибки
  * @param p$subcode    доп код ошибки
  * @param p$msg        текст сообщения
  * @param p$common_msg общий текст ошибки
  * @param p$param1     параметр1 в шаблоне
  * @param p$value1     значение параметра1
  * @param p$param2     параметр2 в шаблоне
  * @param p$value2     значение параметра2
  * @param p$param3     параметр3 в шаблоне
  * @param p$value3     значение параметра3
  * @param p$param4     параметр4 в шаблоне
  * @param p$value4     значение параметра4
  * @param p$param5     параметр5 в шаблоне
  * @param p$value5     значение параметра5
  * @param p$expected   документированная ошибка или нет
  * @param p$stack      sql текст ошибки
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
      -- для недокументированной ошибки добавим стэк
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
  * Получить имя параметра идентификатора абонента по-умолчанию
  * @param p$srvnum код услуги
  * 
  * @return строка
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
  * Проверка возможности платежа
  * @param p$req запись запроса
  * @param p$outp массив входящих параметров
  * @param p$inp  массив исходящих параметров
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
  * Подтверждение платежа
  * @param p$req запись запроса
  * @param p$outp массив входящих параметров
  * @param p$inp  массив исходящих параметров
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
  * Отмена платежа
  * @param p$req запись запроса
  * @param p$outp массив входящих параметров
  * @param p$inp  массив исходящих параметров
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
  * Запрос ловушки  от клиента
  * @param req_id     идентификатор запроса
  * @param req_type   тип запроса
  * @param result     код ошибки запроса
  * @param errmsg     текст ошибки запроса
  * @param timeout    тайм-аут выполнения ловушки.
  * @param oper_type  тип операции
  * @param ppp_id     идентификатор ППП, где совершается операция
  * @param user_id    идентификатор пользователя, совершающего операцию
  * @param agent_id   идентификатор агента, где совершается операция
  * @param prv_id     идентификатор поставщика услуг
  * @param service_id номер услуги, по которой, совершается операция
  * @param prog_id    идентификатор АРМа из которого выполняется операция
  * @param acc_pu     счет абонента в системе ПУ
  * @param summ       сумма операции
  * @param outp       текст исходящих дополнительных параметров
  * @param inp        текст входящих дополнительных параметров
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
    -- Cтруктура строки запроса
    v$req reqs%ROWTYPE;
  
    -- Массив входящих параметров
    v$outp param_array := param_array();
  
    -- Массив исходящих параметров
    v$inp param_array := param_array();
  
    -- Наименование идентификатора абонента
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
  
    -- Получим идентификатор абонента из параметра
    v$acc_pu_name := get$acc_pu_name(v$req.srvnum);
    IF v$acc_pu_name IS NOT NULL AND v$req.acc_pu IS NULL
    THEN
      v$req.acc_pu := v$outp.get$val(v$acc_pu_name);
    END IF;
  
    -- Создадим запись
    save$req(v$req);
  
    -- Проверка
    IF v$req.req_type = c$rt_req
    THEN
      req$check(v$req, v$outp, v$inp);
    
      v$req.req_state := NULL;
      v$req.ans_stamp := dbms_utility.get_time;
      define$appcode(v$req);
      -- Подтверждение платежа
    ELSIF v$req.req_type = c$rt_confirm
    THEN
      req$confirm(v$req, v$outp, v$inp);
    
      v$req.req_state := NULL;
      v$req.ans_stamp := dbms_utility.get_time;
    
      define$appcode(v$req);
      -- Отмена платежа
    ELSIF v$req.req_type = c$rt_storno
    THEN
      req$storno(v$req, v$outp, v$inp);
    
      v$req.req_state  := NULL;
      v$req.undo_stamp := dbms_utility.get_time;
    
      define$appcode(v$req);
      -- Отмена операции
    ELSIF v$req.req_type IN (c$rt_undo_req, c$rt_undo_pay)
    THEN
      define$appcode(v$req);
      -- При отправке на проводку, проводку(сторно)
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
  
    -- Сохраняем запись
    save$req(v$req);
  
    /** Присвоим исходящую переменную */
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
