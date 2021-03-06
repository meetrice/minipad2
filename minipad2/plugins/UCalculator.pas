unit UCalculator;        // 以下算法对于 -sin5、-a 一类的仍有问题

interface

uses UxlStrUtils, UxlMath, UxlFunctions, UxlClasses, UxlList;

type
   TCalcOptions = record
      Decimal: integer;
      Tri_Degree: boolean;
   end;

   TUserFunction = record
   	Name: widestring;
      Equation: widestring;
   	Params: widestring;
      Expression: widestring;
      LeftDef: widestring;
   end;

   TMatchMode = (mmStart, mmMiddle, mmAll);
   TOprType = (otSinoLeft, otSinoRight, otDual);

   TCalculator = class
   private
      FOptions: TCalcOptions;
		FOprs: array [0..5] of TxlStrList;
		FUserDefs: array of TUserFunction;
		FInternalDefCount: integer;
      FRecurCount: integer;

		function f_Calc (s_expr: widestring): widestring;
		procedure f_CheckOpr (o_list, o_oprlist: TxlStrList; ot: TOprType);
		function f_CalcSinoExpr (const s_opr, s_number: widestring): widestring;
		function f_CalcDuoExpr (const s_opr, s_number1, s_number2: widestring): widestring;
      procedure f_raiseerror(const s_msg: widestring = 'error!');
		procedure f_ParseExpr (const s_expr: widestring; o_list: TxlStrList);
		function f_ParseUserFunction (const s_equation, s_params, s_data: widestring): widestring;
		procedure f_SplitExpr (o_list: TxlStrList; const opr: widestring; b_skipbracket: boolean; mmMode: TMatchMode);
      function ParamSeparator (): widestring;
   public
   	constructor Create ();
   	destructor Destroy (); override;
      procedure SetOptions (const value: TCalcOptions);

      procedure AddUserFunction (const s_def: widestring);
		procedure ClearUserFunctions ();

      function Calc (s_expr: widestring): widestring;
   end;

implementation

uses SysUtils, UxlFile, UGlobalObj, UxlCommDlgs;

constructor TCalculator.Create ();
var i: integer;
const
	s_sino: array[0 .. 20] of widestring = ('lg', 'ln', 'exp', 'sqrt', 'sqr', 'rad', 'deg', 'asin', 'arcsin', 'sin', 'acos', 'arccos', 'cos', 'atan', 'arctan', 'tg', 'tan',
   'acot', 'arccot', 'cot', 'int');    //sqrt须在sqr之前，不然永远检索到sqr. 同样, asin 需在 sin 之前
begin
	for i := Low(FOprs) to High(FOprs) do
		FOprs[i] := TxlStrList.Create;
		
	FOprs[0].add ('(');
	FOprs[0].add (')');

   FOprs[1].Add('%');

	for i := Low(s_sino) to High(s_sino) do
		FOprs[2].add (s_sino[i]);

	FOprs[3].add ('^');
	FOprs[4].add ('*');
	FOprs[4].add ('/');
   FOprs[4].add ('\');
   FOprs[4].add ('!');
	FOprs[5].add ('+');
	FOprs[5].add ('-');

   AddUserFunction ('pi=' + FloatToStr(pi));
   AddUserFunction ('e=' + FloatToStr(e));
   AddUserFunction ('log(x' + ParamSeparator + 'y)=lgx/lgy');
   AddUserFunction ('round(x' + ParamSeparator + 'y)=int(x*10^y)/10^y');
   FInternalDefCount := 4;
end;

destructor TCalculator.Destroy ();
var i: integer;
begin
	for i := Low(FOprs) to High(FOprs) do
		FOprs[i].Free;
	ClearUserFunctions;
   inherited;
end;
	
procedure TCalculator.SetOptions (const value: TCalcOptions);
begin
	FOptions := value;
end;

procedure TCalculator.AddUserFunction (const s_def: widestring);
	procedure f_Remove (var s: widestring; const s_remove: widestring);
   var i_pos: integer;
   begin
   	s := Trim(s);
      i_pos := FirstPos (s_remove, s);
      if i_pos > 1 then
         s := LeftStr (s, i_pos - 1);
   end;
var i, j, k, n: integer;
	s, s_name: widestring;
label final;
begin
	s := LowerCase(s_def);
   f_Remove (s, #9);
   f_Remove (s, '//');
   s := TrimInside (s);
   i := FirstPos ('=', s);
   if i <= 0 then exit;

   s_name := LeftStr (s, i - 1);
   n := Length(FUserDefs);
   for k := 0 to n - 1 do
   	if FUserDefs[k].LeftDef = s_name then
			goto final;

	SetLength (FUserDefs, n + 1);
   k := n;
   FUserDefs[k].LeftDef := s_name;
   j := FirstPos ('(', s_name);
   if j > 0 then
   begin
   	FUserDefs[k].Name := LeftStr (s_name, j - 1);
      FUserDefs[k].Params := ReplaceStr (MidStr(s_name, j+1), ')', '');
   end
   else
      FUserDefs[k].Name := s_name;

final:
   FUserDefs[k].Expression := s_def;
   FUserDefs[k].Equation := '(' + MidStr (s, i + 1) + ')';
end;

procedure TCalculator.ClearUserFunctions ();
begin
	SetLength (FUserDefs, FInternalDefCount);
end;

function TCalculator.Calc (s_expr: widestring): widestring;
	function f_ShowHelp (): widestring;
   begin
      result := 'supports pi, e, +, -, *, /, ^, %, lg, ln, log, exp, sqrt, sqr, rad, deg, sin, asin/arcsin, cos, acos/arccos, tg/tan, atan/arctan, cot, acot/arccot';
	end;
   function f_ListUserFuncs (): widestring;
   var i: integer;
   	o_list: TxlStrList;
   begin
   	o_list := TxlStrList.Create;
   	for i := Low(FUserDefs) + FInternalDefCount to High(FUserDefs) do
      	o_list.Add (FUserDefs[i].Expression);
      result := o_list.Text;
      o_list.Free;
   end;
   function f_HelpFunction (const s_func: widestring): widestring;
   var i: integer;
   begin
   	result := '';
   	for i := Low(FUserDefs) + FInternalDefCount to High(FUserDefs) do
      	if IsSameStr(FUserDefs[i].Name, s_func) then
         begin
         	result := FUserDefs[i].Expression;
            exit;
         end;
   end;
var d_expr, d_base: Extended;
	i, i_expo: integer;
begin
   s_expr := lowerCase(TrimInside (s_expr));
   if s_expr = '' then exit;

   if s_expr = '?' then
      result := f_ShowHelp
   else if s_expr = '?list' then
   	result := #13#10 + f_ListUserFuncs
   else if s_expr[1] = '?' then
   	result := f_HelpFunction (MidStr(s_expr, 2))
   else
      try
   		s_expr := ReplaceStrings (s_expr, ['{', '}', '[', ']', '×', '÷', '＋', '－', '＊', '／'], ['(', ')', '(', ')', '*', '/', '+', '-', '*', '/']);
      	FRecurCount := 0;
         d_expr := StrToFloat (f_Calc (s_expr));
         if IsZero (d_expr) then
            result := '0'
         else if IsInfinite (d_expr) or IsNan(d_expr) then
         	f_raiseerror ('Floating point overflow!')
         else if abs(d_expr) > 1E15 then  // 极大整数使用科学计数法
         begin
            GetBaseExpo (d_expr, d_base, i_expo);
            result := FloatToStr(SetDecimal (d_base, Foptions.decimal)) + 'E' + IntToStr(i_expo);
         end
         else    // 取小数位数
         begin
            d_expr := SetDecimal (d_expr, Foptions.decimal);
            result := FloatToStr ( d_expr );
         end;
      except
         on exc: Exception do result := exc.Message;
      end;
end;

function TCalculator.f_Calc (s_expr: widestring): widestring;
var i, k: integer;
   o_list: TxlStrList;
begin
	inc (FRecurCount);
   if FRecurCount > 200 then f_raiseerror ('Infinite recurrence!');

	result := '';
	if s_expr = '' then exit;

   o_list := TxlStrList.Create;
   o_list.separator := '';
   try
   	while true do
      begin
      	f_ParseExpr (s_expr, o_list);
         if o_list.text = s_expr then break;
         s_expr := o_list.text;
         o_list.clear;
      end;

      // 消除括号
      i := o_list.Low;
      while i <= o_list.High do
      begin
			if o_list[i] = '(' then
         begin
         	o_list[i] := f_Calc (o_list[i+1]);
            o_list.Delete (i+1, 2);
         end;
         inc (i);
      end;

      // 单目运算符
      f_CheckOpr (o_list, FOprs[1], otSinoRight);
      f_CheckOpr (o_list, FOprs[2], otSinoLeft);

      // 双目运算符
      for k := 3 to High(FOprs) do
         f_CheckOpr (o_list, FOprs[k], otDual);

      o_list.separator := '';
      result := o_list.Text;
   finally
   	o_list.free;
   end;
   dec (FRecurCount);
end;

procedure TCalculator.f_ParseExpr (const s_expr: widestring; o_list: TxlStrList);
var o_def: TUserFunction;
	i, j, k: integer;
begin
   // 解析括号。不解析括号内的内容
   j := 0;
   k := 1;
   for i := 1 to Length(s_expr) do
      if s_expr[i] = '(' then
      begin
      	inc (j);
         if j = 1 then
         begin
         	if i > k then
            	o_list.add (SubStr(s_expr, k, i - 1));
            o_list.add ('(');
            k := i + 1;
         end;
      end
      else if s_expr[i] = ')' then
      begin
      	dec (j);
         if j = 0 then
         begin
           	o_list.add (SubStr(s_expr, k, i - 1));
            o_list.add (')');
            k := i + 1;
         end
         else if j < 0 then
         	f_raiseerror ('bracket not match!');
      end;
   if j <> 0 then f_raiseerror ('bracket not match!');
   o_list.add (MidStr(s_expr, k));

   // 解析 +、-、*、/、^
	for i := 3 to HIgh(FOprs) do
		for j := FOprs[i].Low to FOprs[i].High do
			f_SplitExpr (o_list, FOprs[i][j], true, mmMiddle);

   // 解析内置函数与%
   for i := FOprs[1].Low to FOprs[1].High do
   	f_SplitExpr (o_list, FOprs[1][i], true, mmMiddle);
   for i := FOprs[2].Low to FOprs[2].High do
   	f_SplitExpr (o_list, FOprs[2][i], true, mmStart);

	// 解析负号  // 由于解析-时用了 mmMiddle，此处似已不必要
//	i := o_list.Low;
//	while i < o_list.High do
//	begin
//		if (o_list[i] = '-') and ((i = o_list.Low) or ((not IsValidNumber(o_list[i - 1])) and IsValidNumber (o_list[i + 1]))) then
//		begin
//			o_list.Delete (i);
//			o_list[i] := '-' + o_list[i];
//		end;
//		inc (i);
//	end;
   
	// 解析展开常数与自定义函数
	for i := Low(FUserDefs) to High(FUserDefs) do
   begin
      o_def := FUserDefs[i];
      j := o_list.Low;
		while j <= o_list.High do
		begin
			if o_list[j] = o_def.Name then
         begin
         	if o_def.Params <> '' then     // 函数形参数 >0
            begin
               if j + 3 >= o_list.Count then f_raiseerror;
               if (o_list[j+1] <> '(') or (o_list[j+3] <> ')') then f_raiseerror;
               o_list.Delete (j);
               o_list[j+1] := f_ParseUserFunction (o_def.Equation, o_def.Params, o_list[j+1]);
            end
            else
         		o_list[j] := o_def.Equation;
         end;
         inc (j);
		end;
   end;
end;

procedure TCalculator.f_SplitExpr (o_list: TxlStrList; const opr: widestring; b_skipbracket: boolean; mmMode: TMatchMode);
var k, l: integer;
	s: widestring;
label l_check;
begin
   k := o_list.Low;
   while k <= o_list.High do
      if (o_list[k] = '(') and b_skipbracket then
         inc (k, 3)
      else
      begin
         s := o_list[k];
         if (FOprs[1].ItemExists (s)) or (FOprs[2].ItemExists(s)) then
         	inc (k)
         else
         begin
            l := FirstPos (opr, s);
l_check:    if (l <= 0) or ((l > 1) and (mmMode = mmStart)) then
               inc (k)
            else if ((l = 1) and (mmMode = mmMiddle) and (o_list[k-1] <> ')')) then
            begin
            	l := FirstPos (opr, s, l + 1);
               goto l_check;
            end
            else
            begin
               o_list.Insert (k, opr);
               if l > 1 then
               begin
                  o_list.Insert (k, LeftStr(s, l - 1));
                  inc (k);
               end;
               inc (k);
               o_list[k] := MidStr (s, l + length(opr));
               if o_list[k] = '' then o_list.Delete (k);
            end;
         end;
      end;
end;

function TCalculator.f_ParseUserFunction (const s_equation, s_params, s_data: widestring): widestring;
var o_paramlist, o_datalist, o_expr: TxlStrList;
	i, j: integer;
begin
   o_paramlist := TxlStrList.Create();   // 函数实参
   o_datalist := TxlStrList.Create();    // 函数实参
   try
      o_paramlist.Separator := ParamSeparator;
      o_paramlist.Text := s_params;
      o_datalist.Separator := ParamSeparator;
      o_datalist.Text := s_data;
      if o_paramlist.count <> o_datalist.Count then f_raiseerror ('parameter list not fit!');

      o_expr := TxlStrList.Create;
      o_expr.text := s_equation;

      for i := FOprs[0].Low to FOprs[0].High do
      	f_SplitExpr (o_expr, FOprs[0][i], false, mmAll);
      for i := 3 to HIgh(FOprs) do
         for j := FOprs[i].Low to FOprs[i].High do
				f_SplitExpr (o_expr, FOprs[i][j], false, mmMiddle);
      for i := FOprs[1].Low to FOprs[1].High do
      	f_SplitExpr (o_expr, FOprs[1][i], false, mmMiddle);
      for i := FOprs[2].Low to FOprs[2].High do
      	f_SplitExpr (o_expr, FOprs[2][i], false, mmStart);

      for i := o_expr.Low to o_expr.High do
         for j := o_paramlist.Low to o_paramList.High do   // 形参替换为实参
            if o_expr[i] = o_ParamList[j] then o_expr[i] := '(' + o_datalist[j] + ')';
      o_expr.separator := '';
      result := o_expr.text;
      o_expr.free;
   finally
      o_paramlist.free;
      o_datalist.free;
   end;
end;

procedure TCalculator.f_CheckOpr (o_list, o_oprlist: TxlStrList; ot: TOprType);
var i: integer;
begin
   i := o_list.Low;
   while i <= o_list.High do
   begin
      if o_oprlist.ItemExists (o_list[i]) then
      begin
         if (i = o_list.High) and (ot <> otSinoRight) then f_raiseerror;
         if (i = o_list.Low) and (ot <> otSinoLeft) then f_raiseerror;
         case ot of
         	otSinoRight:
            	begin
                  o_list[i-1] := f_CalcSinoExpr (o_list[i], o_list[i-1]);
                  o_list.Delete(i);
               end;
				otSinoLeft:
               begin
                  o_list[i] := f_CalcSinoExpr (o_list[i], o_list[i + 1]);
                  o_list.Delete (i + 1);
                  inc (i);
               end;
            else
            begin
               o_list[i - 1] := f_CalcDuoExpr (o_list[i], o_list[i - 1], o_list[i + 1]);
               o_list.Delete (i, 2);
            end;
         end;
      end
      else
      	inc (i);
   end;
end;

function TCalculator.f_CalcSinoExpr (const s_opr, s_number: widestring): widestring;
var f1, g: Extended;
begin
	f1 := StrToFloat (s_number);
		
	if ((s_opr = 'sin') or (s_opr = 'cos') or (s_opr = 'tan') or (s_opr = 'tg') or (s_opr = 'cot'))
		and FOptions.Tri_Degree then f1 := rad (f1); // 使用角度制进行三角计算

   if s_opr = '%' then
   	g := f1 / 100
   else if s_opr = 'sin' then
   	g := sin(f1)
   else if s_opr = 'cos' then
   	g := cos(f1)
   else if (s_opr = 'tan') or (s_opr = 'tg') then
     	g := sin(f1) / cos(f1)
   else if s_opr = 'cot' then
     	g := cos(f1) / sin(f1)
   else if (s_opr = 'asin') or (s_opr = 'arcsin') then
      g := ArcSin (f1)
   else if (s_opr = 'acos') or (s_opr = 'arccos') then
   	g := ArcCos (f1)
   else if (s_opr = 'atan') or (s_opr = 'arctan') then
   	g := ArcTan(f1)
   else if (s_opr = 'acot') or (s_opr = 'arccot') then
   	g := ArcCot (f1)
   else if s_opr = 'exp' then
   	g := exp(f1)
   else if (s_opr = 'lg') then
   	g := log10(f1)
   else if s_opr = 'sqrt' then
   	g := sqrt (f1)
   else if s_opr = 'sqr'then
   	g := sqr(f1)
   else if s_opr = 'ln' then
   	g := ln (f1)
   else if s_opr = 'rad' then
      g := rad (f1)
   else if s_opr = 'deg' then
      g := deg (f1)
   else if s_opr = 'int' then
      g := Round (f1);

   if ((s_opr ='asin') or (s_opr = 'arcsin') or (s_opr = 'acos') or (s_opr = 'arccos') or (s_opr = 'atan') or (s_opr = 'arctan')
   	or (s_opr = 'acot') or (s_opr = 'arccot')) and FOptions.Tri_Degree then
      	g := deg (g);
	result := FloatToStr (g);
end;

function TCalculator.f_CalcDuoExpr (const s_opr, s_number1, s_number2: widestring): widestring;
var f1, f2, g: Extended;
   i, j, k: integer;
begin
   if (s_opr = '\') or (s_opr = '!') then
   begin
      i := StrToInt (s_number1);
      j := StrToInt (s_number2);

      if s_opr = '\' then
         k := i div j
      else if s_opr = '!' then
         k := i mod j;

      result := IntToStr (k);
   end
   else
   begin
      f1 := StrToFloat (s_number1);
      f2 := StrToFloat (s_number2);

      if s_opr = '^' then
         g := power(f1, f2)
      else if s_opr = '*' then
         g := f1 * f2
      else if s_opr = '/' then
         g := f1 / f2
      else if s_opr = '+' then
         g := f1 + f2
      else if s_opr = '-' then
         g := f1 - f2;

      result := FloatToStr (g);
   end;
end;

procedure TCalculator.f_RaiseError (const s_msg: widestring = 'error!');
begin
	raise Exception.create (s_msg);
end;

function TCalculator.ParamSeparator (): widestring;
begin
   if sDot = '.' then
      result := ','
   else
      result := ';';
end;

end.

