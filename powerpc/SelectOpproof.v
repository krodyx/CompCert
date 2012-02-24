(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

(** Correctness of instruction selection for operators *)

Require Import Coqlib.
Require Import Maps.
Require Import AST.
Require Import Integers.
Require Import Floats.
Require Import Values.
Require Import Memory.
Require Import Events.
Require Import Globalenvs.
Require Import Smallstep.
Require Import Cminor.
Require Import Op.
Require Import CminorSel.
Require Import SelectOp.

Open Local Scope cminorsel_scope.

Section CMCONSTR.

Variable ge: genv.
Variable sp: val.
Variable e: env.
Variable m: mem.

(** * Useful lemmas and tactics *)

(** The following are trivial lemmas and custom tactics that help
  perform backward (inversion) and forward reasoning over the evaluation
  of operator applications. *)  

Ltac EvalOp := eapply eval_Eop; eauto with evalexpr.

Ltac InvEval1 :=
  match goal with
  | [ H: (eval_expr _ _ _ _ _ (Eop _ Enil) _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_expr _ _ _ _ _ (Eop _ (_ ::: Enil)) _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_expr _ _ _ _ _ (Eop _ (_ ::: _ ::: Enil)) _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_exprlist _ _ _ _ _ Enil _) |- _ ] =>
      inv H; InvEval1
  | [ H: (eval_exprlist _ _ _ _ _ (_ ::: _) _) |- _ ] =>
      inv H; InvEval1
  | _ =>
      idtac
  end.

Ltac InvEval2 :=
  match goal with
  | [ H: (eval_operation _ _ _ nil _ = Some _) |- _ ] =>
      simpl in H; inv H
  | [ H: (eval_operation _ _ _ (_ :: nil) _ = Some _) |- _ ] =>
      simpl in H; FuncInv
  | [ H: (eval_operation _ _ _ (_ :: _ :: nil) _ = Some _) |- _ ] =>
      simpl in H; FuncInv
  | [ H: (eval_operation _ _ _ (_ :: _ :: _ :: nil) _ = Some _) |- _ ] =>
      simpl in H; FuncInv
  | _ =>
      idtac
  end.

Ltac InvEval := InvEval1; InvEval2; InvEval2.

Ltac TrivialExists :=
  match goal with
  | [ |- exists v, _ /\ Val.lessdef ?a v ] => exists a; split; [EvalOp | auto]
  end.

(** * Correctness of the smart constructors *)

(** We now show that the code generated by "smart constructor" functions
  such as [SelectOp.notint] behaves as expected.  Continuing the
  [notint] example, we show that if the expression [e]
  evaluates to some value [v], then [SelectOp.notint e]
  evaluates to a value [v'] which is either [Val.notint v] or more defined
  than [Val.notint v].

  All proofs follow a common pattern:
- Reasoning by case over the result of the classification functions
  (such as [add_match] for integer addition), gathering additional
  information on the shape of the argument expressions in the non-default
  cases.
- Inversion of the evaluations of the arguments, exploiting the additional
  information thus gathered.
- Equational reasoning over the arithmetic operations performed,
  using the lemmas from the [Int], [Float] and [Value] modules.
- Construction of an evaluation derivation for the expression returned
  by the smart constructor.
*)

Definition unary_constructor_sound (cstr: expr -> expr) (sem: val -> val) : Prop :=
  forall le a x,
  eval_expr ge sp e m le a x ->
  exists v, eval_expr ge sp e m le (cstr a) v /\ Val.lessdef (sem x) v.

Definition binary_constructor_sound (cstr: expr -> expr -> expr) (sem: val -> val -> val) : Prop :=
  forall le a x b y,
  eval_expr ge sp e m le a x ->
  eval_expr ge sp e m le b y ->
  exists v, eval_expr ge sp e m le (cstr a b) v /\ Val.lessdef (sem x y) v.

Theorem eval_addrsymbol:
  forall le id ofs,
  exists v, eval_expr ge sp e m le (addrsymbol id ofs) v /\ Val.lessdef (symbol_address ge id ofs) v.
Proof.
  intros. unfold addrsymbol. econstructor; split. 
  EvalOp. simpl; eauto. 
  auto.
Qed.

Theorem eval_addrstack:
  forall le ofs,
  exists v, eval_expr ge sp e m le (addrstack ofs) v /\ Val.lessdef (Val.add sp (Vint ofs)) v.
Proof.
  intros. unfold addrstack. econstructor; split.
  EvalOp. simpl; eauto. 
  auto.
Qed.

Theorem eval_notint: unary_constructor_sound notint Val.notint.
Proof.
  assert (forall v, Val.lessdef (Val.notint (Val.notint v)) v).
    destruct v; simpl; auto. rewrite Int.not_involutive; auto.
  unfold notint; red; intros until x; case (notint_match a); intros; InvEval.
  TrivialExists.
  subst. exists v1; split; auto.
  subst. TrivialExists. 
  subst. TrivialExists.
  subst. TrivialExists.
  subst. exists (Val.and v1 v0); split; auto. EvalOp.
  subst. exists (Val.or v1 v0); split; auto. EvalOp.
  subst. exists (Val.xor v1 v0); split; auto. EvalOp.
  subst. exists (Val.or v0 (Val.notint v1)); split. EvalOp. 
    destruct v0; destruct v1; simpl; auto. rewrite Int.not_and_or_not. rewrite Int.not_involutive.
    rewrite Int.or_commut. auto.
  subst. exists (Val.and v0 (Val.notint v1)); split. EvalOp. 
    destruct v0; destruct v1; simpl; auto. rewrite Int.not_or_and_not. rewrite Int.not_involutive.
    rewrite Int.and_commut. auto.
  TrivialExists. 
Qed.

Theorem eval_boolval: unary_constructor_sound boolval Val.boolval.
Proof.
  assert (DFL: 
    forall le a x,
    eval_expr ge sp e m le a x ->
     exists v, eval_expr ge sp e m le (Eop (Ocmp (Ccompuimm Cne Int.zero)) (a ::: Enil)) v
           /\ Val.lessdef (Val.boolval x) v).
  intros. TrivialExists. simpl. destruct x; simpl; auto.

  red. induction a; simpl; intros; eauto. destruct o; eauto.
(* intconst *)
  destruct e0; eauto. InvEval. TrivialExists. simpl. destruct (Int.eq i Int.zero); auto.
(* cmp *)
  inv H. simpl in H5.
  destruct (eval_condition c vl m) as []_eqn. 
  TrivialExists. simpl. inv H5. rewrite Heqo. destruct b; auto.
  simpl in H5. inv H5. 
  exists Vundef; split; auto. EvalOp; simpl. rewrite Heqo; auto.

(* condition *)
  inv H. destruct v1.
  exploit IHa1; eauto. intros [v [A B]]. exists v; split; auto. eapply eval_Econdition; eauto. 
  exploit IHa2; eauto. intros [v [A B]]. exists v; split; auto. eapply eval_Econdition; eauto. 
Qed.

Theorem eval_notbool: unary_constructor_sound notbool Val.notbool.
Proof.
  assert (DFL: 
    forall le a x,
    eval_expr ge sp e m le a x ->
     exists v, eval_expr ge sp e m le (Eop (Ocmp (Ccompuimm Ceq Int.zero)) (a ::: Enil)) v
           /\ Val.lessdef (Val.notbool x) v).
  intros. TrivialExists. simpl. destruct x; simpl; auto.

  red. induction a; simpl; intros; eauto. destruct o; eauto.
(* intconst *)
  destruct e0; eauto. InvEval. TrivialExists. simpl. destruct (Int.eq i Int.zero); auto.
(* cmp *)
  inv H. simpl in H5.
  destruct (eval_condition c vl m) as []_eqn. 
  TrivialExists. simpl. rewrite (eval_negate_condition _ _ _ Heqo). destruct b; inv H5; auto.
  inv H5. simpl. 
  destruct (eval_condition (negate_condition c) vl m) as []_eqn.
  destruct b; [exists Vtrue | exists Vfalse]; split; auto; EvalOp; simpl. rewrite Heqo0; auto. rewrite Heqo0; auto.
  exists Vundef; split; auto; EvalOp; simpl. rewrite Heqo0; auto.
(* condition *)
  inv H. destruct v1.
  exploit IHa1; eauto. intros [v [A B]]. exists v; split; auto. eapply eval_Econdition; eauto. 
  exploit IHa2; eauto. intros [v [A B]]. exists v; split; auto. eapply eval_Econdition; eauto. 
Qed.

Theorem eval_addimm:
  forall n, unary_constructor_sound (addimm n) (fun x => Val.add x (Vint n)).
Proof.
  red; unfold addimm; intros until x.
  predSpec Int.eq Int.eq_spec n Int.zero.
  subst n. intros. exists x; split; auto. 
  destruct x; simpl; auto. rewrite Int.add_zero. auto. rewrite Int.add_zero. auto.
  case (addimm_match a); intros; InvEval; simpl; TrivialExists; simpl.
  rewrite Int.add_commut. auto.
  unfold symbol_address. destruct (Genv.find_symbol ge s); simpl; auto. rewrite Int.add_commut; auto.
  rewrite Val.add_assoc. rewrite Int.add_commut. auto.
  subst x. rewrite Val.add_assoc. rewrite Int.add_commut. auto.
Qed. 

Theorem eval_add: binary_constructor_sound add Val.add.
Proof.
  red; intros until y.
  unfold add; case (add_match a b); intros; InvEval.
  rewrite Val.add_commut. apply eval_addimm; auto.
  subst. 
  replace (Val.add (Val.add v1 (Vint n1)) (Val.add v0 (Vint n2)))
     with (Val.add (Val.add v1 v0) (Val.add (Vint n1) (Vint n2))).
  apply eval_addimm. EvalOp.
  repeat rewrite Val.add_assoc. decEq. apply Val.add_permut.
  subst. 
  replace (Val.add (Val.add v1 (Vint n1)) y)
     with (Val.add (Val.add v1 y) (Vint n1)).
  apply eval_addimm. EvalOp.
  repeat rewrite Val.add_assoc. decEq. apply Val.add_commut.
  subst. TrivialExists. 
    econstructor. EvalOp. simpl. reflexivity. econstructor. eauto. constructor. 
    simpl. rewrite (Val.add_commut v1). rewrite <- Val.add_assoc. decEq; decEq. 
    unfold symbol_address. destruct (Genv.find_symbol ge s); auto.
  subst. TrivialExists.
    econstructor. EvalOp. simpl. reflexivity. econstructor. eauto. constructor. 
    simpl. repeat rewrite Val.add_assoc. decEq; decEq.
    rewrite Val.add_commut. rewrite Val.add_permut. auto.
  apply eval_addimm; auto.
  subst. rewrite <- Val.add_assoc. apply eval_addimm. EvalOp.
  TrivialExists. 
Qed.

Theorem eval_sub: binary_constructor_sound sub Val.sub.
Proof.
  red; intros until y.
  unfold sub; case (sub_match a b); intros; InvEval.
  rewrite Val.sub_add_opp. apply eval_addimm; auto.
  subst. rewrite Val.sub_add_l. rewrite Val.sub_add_r. 
    rewrite Val.add_assoc. simpl. rewrite Int.add_commut. rewrite <- Int.sub_add_opp.
    apply eval_addimm; EvalOp.
  subst. rewrite Val.sub_add_l. apply eval_addimm; EvalOp.
  subst. rewrite Val.sub_add_r. apply eval_addimm; EvalOp.
  TrivialExists.
Qed.

Theorem eval_negint: unary_constructor_sound negint (fun v => Val.sub Vzero v).
Proof.
  red; intros. unfold negint. TrivialExists.
Qed.

Lemma eval_rolm:
  forall amount mask,
  unary_constructor_sound (fun a => rolm a amount mask)
                          (fun x => Val.rolm x amount mask).
Proof.
  red; intros until x. unfold rolm; case (rolm_match a); intros; InvEval.
  TrivialExists. 
  subst. rewrite Val.rolm_rolm. TrivialExists.
  subst. rewrite <- Val.rolm_zero. rewrite Val.rolm_rolm.
  rewrite (Int.add_commut Int.zero). rewrite Int.add_zero. TrivialExists.
  TrivialExists.
Qed.

Theorem eval_shlimm:
  forall n, unary_constructor_sound (fun a => shlimm a n)
                                    (fun x => Val.shl x (Vint n)).
Proof.
  red; intros.  unfold shlimm.
  predSpec Int.eq Int.eq_spec n Int.zero.
  subst. exists x; split; auto. destruct x; simpl; auto. rewrite Int.shl_zero; auto.
  destruct (Int.ltu n Int.iwordsize) as []_eqn. 
  rewrite Val.shl_rolm; auto. apply eval_rolm; auto. 
  TrivialExists. econstructor. eauto. econstructor. EvalOp. simpl; eauto. constructor. auto.
Qed.

Theorem eval_shrimm:
  forall n, unary_constructor_sound (fun a => shrimm a n)
                                    (fun x => Val.shr x (Vint n)).
Proof.
  red; intros.  unfold shrimm.
  predSpec Int.eq Int.eq_spec n Int.zero.
  subst. exists x; split; auto. destruct x; simpl; auto. rewrite Int.shr_zero; auto.
  TrivialExists.
Qed.

Theorem eval_shruimm:
  forall n, unary_constructor_sound (fun a => shruimm a n)
                                    (fun x => Val.shru x (Vint n)).
Proof.
  red; intros.  unfold shruimm.
  predSpec Int.eq Int.eq_spec n Int.zero.
  subst. exists x; split; auto. destruct x; simpl; auto. rewrite Int.shru_zero; auto.
  destruct (Int.ltu n Int.iwordsize) as []_eqn. 
  rewrite Val.shru_rolm; auto. apply eval_rolm; auto. 
  TrivialExists. econstructor. eauto. econstructor. EvalOp. simpl; eauto. constructor. auto.
Qed.

Lemma eval_mulimm_base:
  forall n, unary_constructor_sound (mulimm_base n) (fun x => Val.mul x (Vint n)).
Proof.
  intros; red; intros; unfold mulimm_base. 
  generalize (Int.one_bits_decomp n). 
  generalize (Int.one_bits_range n).
  destruct (Int.one_bits n).
  intros. TrivialExists. 
  destruct l.
  intros. rewrite H1. simpl. 
  rewrite Int.add_zero.
  replace (Vint (Int.shl Int.one i)) with (Val.shl Vone (Vint i)). rewrite Val.shl_mul.
  apply eval_shlimm. auto. simpl. rewrite H0; auto with coqlib.
  destruct l.
  intros. rewrite H1. simpl.
  exploit (eval_shlimm i (x :: le) (Eletvar 0) x). constructor; auto. intros [v1 [A1 B1]].
  exploit (eval_shlimm i0 (x :: le) (Eletvar 0) x). constructor; auto. intros [v2 [A2 B2]].
  exists (Val.add v1 v2); split.
  econstructor. eauto. EvalOp.
  rewrite Int.add_zero.
  replace (Vint (Int.add (Int.shl Int.one i) (Int.shl Int.one i0)))
     with (Val.add (Val.shl Vone (Vint i)) (Val.shl Vone (Vint i0))).
  rewrite Val.mul_add_distr_r.
  repeat rewrite Val.shl_mul. apply Val.add_lessdef; auto. 
  simpl. repeat rewrite H0; auto with coqlib. 
  intros. TrivialExists. 
Qed.

Theorem eval_mulimm:
  forall n, unary_constructor_sound (mulimm n) (fun x => Val.mul x (Vint n)).
Proof.
  intros; red; intros until x; unfold mulimm.
  predSpec Int.eq Int.eq_spec n Int.zero. 
  intros. exists (Vint Int.zero); split. EvalOp. 
  destruct x; simpl; auto. subst n. rewrite Int.mul_zero. auto.
  predSpec Int.eq Int.eq_spec n Int.one.
  intros. exists x; split; auto.
  destruct x; simpl; auto. subst n. rewrite Int.mul_one. auto.
  case (mulimm_match a); intros; InvEval.
  TrivialExists. simpl. rewrite Int.mul_commut; auto.
  subst. rewrite Val.mul_add_distr_l. 
  exploit eval_mulimm_base; eauto. instantiate (1 := n). intros [v' [A1 B1]].
  exploit (eval_addimm (Int.mul n n2) le (mulimm_base n t2) v'). auto. intros [v'' [A2 B2]].
  exists v''; split; auto. eapply Val.lessdef_trans. eapply Val.add_lessdef; eauto. 
  rewrite Val.mul_commut; auto.
  apply eval_mulimm_base; auto.
Qed.

Theorem eval_mul: binary_constructor_sound mul Val.mul.
Proof.
  red; intros until y.
  unfold mul; case (mul_match a b); intros; InvEval.
  rewrite Val.mul_commut. apply eval_mulimm. auto. 
  apply eval_mulimm. auto.
  TrivialExists.
Qed.

Theorem eval_andimm:
  forall n, unary_constructor_sound (andimm n) (fun x => Val.and x (Vint n)).
Proof.
  intros; red; intros until x. unfold andimm. case (andimm_match a); intros.
  InvEval. TrivialExists. simpl. rewrite Int.and_commut; auto.
  set (n' := Int.and n n2). 
  destruct (Int.eq (Int.shru (Int.shl n' amount) amount) n' &&
            Int.ltu amount Int.iwordsize) as []_eqn.
  InvEval. destruct (andb_prop _ _ Heqb). 
  generalize (Int.eq_spec (Int.shru (Int.shl n' amount) amount) n'). rewrite H1; intros.
  replace (Val.and x (Vint n))
     with (Val.rolm v0 (Int.sub Int.iwordsize amount) (Int.and (Int.shru Int.mone amount) n')).
  apply eval_rolm; auto.
  subst. destruct v0; simpl; auto. rewrite H3. simpl. decEq. rewrite Int.and_assoc.
  rewrite (Int.and_commut n2 n).
  transitivity (Int.and (Int.shru i amount) (Int.and n n2)).
  rewrite (Int.shru_rolm i); auto. unfold Int.rolm. rewrite Int.and_assoc; auto. 
  symmetry. apply Int.shr_and_shru_and. auto.
  set (e2 := Eop (Oshrimm amount) (t2 ::: Enil)) in *.
  InvEval. subst. rewrite Val.and_assoc. simpl. rewrite Int.and_commut. TrivialExists.  
  InvEval. subst. rewrite Val.and_assoc. simpl. rewrite Int.and_commut. TrivialExists. 
  InvEval. subst. TrivialExists. simpl. 
  destruct v1; auto. simpl. unfold Int.rolm. rewrite Int.and_assoc. 
  decEq. decEq. decEq. apply Int.and_commut.
  destruct (Int.eq (Int.shru (Int.shl n amount) amount) n &&
            Int.ltu amount Int.iwordsize) as []_eqn.
  InvEval. destruct (andb_prop _ _ Heqb). 
  generalize (Int.eq_spec (Int.shru (Int.shl n amount) amount) n). rewrite H0; intros.
  replace (Val.and x (Vint n))
     with (Val.rolm v1 (Int.sub Int.iwordsize amount) (Int.and (Int.shru Int.mone amount) n)).
  apply eval_rolm; auto.
  subst x. destruct v1; simpl; auto. rewrite H1; simpl. decEq. 
  transitivity (Int.and (Int.shru i amount) n).
  rewrite (Int.shru_rolm i); auto. unfold Int.rolm. rewrite Int.and_assoc; auto. 
  symmetry. apply Int.shr_and_shru_and. auto.
  TrivialExists. 
  TrivialExists.
Qed.

Theorem eval_and: binary_constructor_sound and Val.and.
Proof.
  red; intros until y; unfold and; case (and_match a b); intros; InvEval.
  rewrite Val.and_commut. apply eval_andimm; auto.
  apply eval_andimm; auto.
  subst. rewrite Val.and_commut. TrivialExists.
  subst. TrivialExists.
  TrivialExists.
Qed.

Theorem eval_orimm:
  forall n, unary_constructor_sound (orimm n) (fun x => Val.or x (Vint n)).
Proof.
  intros; red; intros until x.
  unfold orimm. destruct (orimm_match a); intros; InvEval.
  TrivialExists. simpl. rewrite Int.or_commut; auto.
  subst. rewrite Val.or_assoc. simpl. rewrite Int.or_commut. TrivialExists. 
  TrivialExists.
Qed.

Remark eval_same_expr:
  forall a1 a2 le v1 v2,
  same_expr_pure a1 a2 = true ->
  eval_expr ge sp e m le a1 v1 ->
  eval_expr ge sp e m le a2 v2 ->
  a1 = a2 /\ v1 = v2.
Proof.
  intros until v2.
  destruct a1; simpl; try (intros; discriminate). 
  destruct a2; simpl; try (intros; discriminate).
  case (ident_eq i i0); intros.
  subst i0. inversion H0. inversion H1. split. auto. congruence. 
  discriminate.
Qed.

Theorem eval_or: binary_constructor_sound or Val.or.
Proof.
  red; intros until y; unfold or; case (or_match a b); intros.
(* rolm - rolm *)
  destruct (Int.eq amount1 amount2 && same_expr_pure t1 t2) as []_eqn.
  destruct (andb_prop _ _ Heqb0).
  generalize (Int.eq_spec amount1 amount2). rewrite H1. intro. subst amount2.
  InvEval. exploit eval_same_expr; eauto. intros [EQ1 EQ2]. subst. 
  rewrite Val.or_rolm. TrivialExists.
  TrivialExists.
(* andimm - rolm *)
  destruct (Int.eq mask1 (Int.not mask2) && is_rlw_mask mask2) as []_eqn.
  destruct (andb_prop _ _ Heqb0). 
  generalize (Int.eq_spec mask1 (Int.not mask2)); rewrite H1; intros.
  InvEval. subst. TrivialExists. 
  TrivialExists.
(* rolm - andimm *)
  destruct (Int.eq mask2 (Int.not mask1) && is_rlw_mask mask1) as []_eqn.
  destruct (andb_prop _ _ Heqb0). 
  generalize (Int.eq_spec mask2 (Int.not mask1)); rewrite H1; intros.
  InvEval. subst. rewrite Val.or_commut. TrivialExists.
  TrivialExists.
(* intconst *)
  InvEval. rewrite Val.or_commut. apply eval_orimm; auto. 
  InvEval. apply eval_orimm; auto.
(* orc *)
  InvEval. subst. rewrite Val.or_commut. TrivialExists.
  InvEval. subst. TrivialExists.
(* default *)
  TrivialExists. 
Qed.

Theorem eval_xorimm:
  forall n, unary_constructor_sound (xorimm n) (fun x => Val.xor x (Vint n)).
Proof.
  intros; red; intros until x.
  unfold xorimm. destruct (xorimm_match a); intros; InvEval.
  TrivialExists. simpl. rewrite Int.xor_commut; auto.
  subst. rewrite Val.xor_assoc. simpl. rewrite Int.xor_commut. TrivialExists. 
  TrivialExists.
Qed.

Theorem eval_xor: binary_constructor_sound xor Val.xor.
Proof.
  red; intros until y; unfold xor; case (xor_match a b); intros; InvEval.
  rewrite Val.xor_commut. apply eval_xorimm; auto.
  apply eval_xorimm; auto.
  TrivialExists.
Qed.

Theorem eval_divs:
  forall le a b x y z,
  eval_expr ge sp e m le a x ->
  eval_expr ge sp e m le b y ->
  Val.divs x y = Some z ->
  exists v, eval_expr ge sp e m le (divs a b) v /\ Val.lessdef z v.
Proof.
  intros. unfold divs. exists z; split. EvalOp. auto.
Qed.

Lemma eval_mod_aux:
  forall divop semdivop,
  (forall sp x y m, eval_operation ge sp divop (x :: y :: nil) m = semdivop x y) ->
  forall le a b x y z,
  eval_expr ge sp e m le a x ->
  eval_expr ge sp e m le b y ->
  semdivop x y = Some z ->
  eval_expr ge sp e m le (mod_aux divop a b) (Val.sub x (Val.mul z y)).
Proof.
  intros; unfold mod_aux.
  eapply eval_Elet. eexact H0. eapply eval_Elet. 
  apply eval_lift. eexact H1.
  eapply eval_Eop. eapply eval_Econs. 
  eapply eval_Eletvar. simpl; reflexivity.
  eapply eval_Econs. eapply eval_Eop. 
  eapply eval_Econs. eapply eval_Eop.
  eapply eval_Econs. apply eval_Eletvar. simpl; reflexivity.
  eapply eval_Econs. apply eval_Eletvar. simpl; reflexivity.
  apply eval_Enil.  
  rewrite H. eauto.
  eapply eval_Econs. apply eval_Eletvar. simpl; reflexivity.
  apply eval_Enil.  
  simpl; reflexivity. apply eval_Enil. 
  reflexivity.
Qed.

Theorem eval_mods:
  forall le a b x y z,
  eval_expr ge sp e m le a x ->
  eval_expr ge sp e m le b y ->
  Val.mods x y = Some z ->
  exists v, eval_expr ge sp e m le (mods a b) v /\ Val.lessdef z v.
Proof.
  intros; unfold mods. 
  exploit Val.mods_divs; eauto. intros [v [A B]].
  subst. econstructor; split; eauto.
  apply eval_mod_aux with (semdivop := Val.divs); auto.
Qed.

Theorem eval_divuimm:
  forall le n a x z,
  eval_expr ge sp e m le a x ->
  Val.divu x (Vint n) = Some z ->
  exists v, eval_expr ge sp e m le (divuimm a n) v /\ Val.lessdef z v.
Proof.
  intros; unfold divuimm. 
  destruct (Int.is_power2 n) as []_eqn. 
  replace z with (Val.shru x (Vint i)). apply eval_shruimm; auto.
  eapply Val.divu_pow2; eauto.
  TrivialExists. 
  econstructor. eauto. econstructor. EvalOp. simpl; eauto. constructor. auto.
Qed.

Theorem eval_divu:
  forall le a x b y z,
  eval_expr ge sp e m le a x ->
  eval_expr ge sp e m le b y ->
  Val.divu x y = Some z ->
  exists v, eval_expr ge sp e m le (divu a b) v /\ Val.lessdef z v.
Proof.
  intros until z. unfold divu; destruct (divu_match b); intros; InvEval.
  eapply eval_divuimm; eauto.
  TrivialExists. 
Qed.

Theorem eval_moduimm:
  forall le n a x z,
  eval_expr ge sp e m le a x ->
  Val.modu x (Vint n) = Some z ->
  exists v, eval_expr ge sp e m le (moduimm a n) v /\ Val.lessdef z v.
Proof.
  intros; unfold moduimm. 
  destruct (Int.is_power2 n) as []_eqn. 
  replace z with (Val.and x (Vint (Int.sub n Int.one))). apply eval_andimm; auto.
  eapply Val.modu_pow2; eauto.
  exploit Val.modu_divu; eauto. intros [v [A B]].
  subst. econstructor; split; eauto.
  apply eval_mod_aux with (semdivop := Val.divu); auto.
  EvalOp.
Qed.

Theorem eval_modu:
  forall le a x b y z,
  eval_expr ge sp e m le a x ->
  eval_expr ge sp e m le b y ->
  Val.modu x y = Some z ->
  exists v, eval_expr ge sp e m le (modu a b) v /\ Val.lessdef z v.
Proof.
  intros until y; unfold modu; case (modu_match b); intros; InvEval.
  eapply eval_moduimm; eauto.
  exploit Val.modu_divu; eauto. intros [v [A B]].
  subst. econstructor; split; eauto.
  apply eval_mod_aux with (semdivop := Val.divu); auto.
Qed.

Theorem eval_shl: binary_constructor_sound shl Val.shl.
Proof.
  red; intros until y; unfold shl; case (shl_match b); intros.
  InvEval. apply eval_shlimm; auto.
  TrivialExists. 
Qed.

Theorem eval_shr: binary_constructor_sound shr Val.shr.
Proof.
  red; intros until y; unfold shr; case (shr_match b); intros.
  InvEval. apply eval_shrimm; auto.
  TrivialExists. 
Qed.

Theorem eval_shru: binary_constructor_sound shru Val.shru.
Proof.
  red; intros until y; unfold shru; case (shru_match b); intros.
  InvEval. apply eval_shruimm; auto.
  TrivialExists. 
Qed.

Theorem eval_negf: unary_constructor_sound negf Val.negf.
Proof.
  red; intros. TrivialExists. 
Qed.

Theorem eval_absf: unary_constructor_sound absf Val.absf.
Proof.
  red; intros. TrivialExists. 
Qed.

Theorem eval_addf: binary_constructor_sound addf Val.addf.
Proof.
  red; intros until y; unfold addf.
  destruct (use_fused_mul tt); simpl.
  case (addf_match a b); intros; InvEval.
  TrivialExists. simpl. congruence.
  TrivialExists. simpl. rewrite Val.addf_commut. congruence.
  intros. TrivialExists.
  intros. TrivialExists.
Qed.
 
Theorem eval_subf: binary_constructor_sound subf Val.subf.
Proof.
  red; intros until y; unfold subf.
  destruct (use_fused_mul tt); simpl.
  case (subf_match a); intros; InvEval.
  TrivialExists. simpl. congruence.
  TrivialExists.
  intros. TrivialExists.
Qed.

Theorem eval_mulf: binary_constructor_sound mulf Val.mulf.
Proof.
  red; intros; TrivialExists.
Qed.

Theorem eval_divf: binary_constructor_sound divf Val.divf.
Proof.
  red; intros; TrivialExists.
Qed.

Theorem eval_comp:
  forall c, binary_constructor_sound (comp c) (Val.cmp c).
Proof.
  intros; red; intros until y. unfold comp; case (comp_match a b); intros; InvEval.
  TrivialExists. simpl. rewrite Val.swap_cmp_bool. auto.
  TrivialExists.
  TrivialExists.
Qed.

Theorem eval_compu:
  forall c, binary_constructor_sound (compu c) (Val.cmpu (Mem.valid_pointer m) c).
Proof.
  intros; red; intros until y. unfold compu; case (compu_match a b); intros; InvEval.
  TrivialExists. simpl. rewrite Val.swap_cmpu_bool. auto.
  TrivialExists.
  TrivialExists.
Qed.

Theorem eval_compf:
  forall c, binary_constructor_sound (compf c) (Val.cmpf c).
Proof.
  intros; red; intros. unfold compf. TrivialExists.
Qed.


Theorem eval_cast8signed: unary_constructor_sound cast8signed (Val.sign_ext 8).
Proof.
  red; intros. unfold cast8signed. TrivialExists.
Qed.

Theorem eval_cast8unsigned: unary_constructor_sound cast8unsigned (Val.zero_ext 8).
Proof.
  red; intros. unfold cast8unsigned.
  rewrite Val.zero_ext_and. apply eval_andimm; auto. compute; auto.
Qed.

Theorem eval_cast16signed: unary_constructor_sound cast16signed (Val.sign_ext 16).
Proof.
  red; intros. unfold cast16signed. TrivialExists.
Qed.

Theorem eval_cast16unsigned: unary_constructor_sound cast16unsigned (Val.zero_ext 16).
Proof.
  red; intros. unfold cast16unsigned.
  rewrite Val.zero_ext_and. apply eval_andimm; auto. compute; auto.
Qed.

Theorem eval_singleoffloat: unary_constructor_sound singleoffloat Val.singleoffloat.
Proof.
  red; intros. unfold singleoffloat. TrivialExists.
Qed.

Theorem eval_intoffloat:
  forall le a x y,
  eval_expr ge sp e m le a x ->
  Val.intoffloat x = Some y ->
  exists v, eval_expr ge sp e m le (intoffloat a) v /\ Val.lessdef y v.
Proof.
  intros; unfold intoffloat. TrivialExists. 
Qed.

Theorem eval_intuoffloat:
  forall le a x y,
  eval_expr ge sp e m le a x ->
  Val.intuoffloat x = Some y ->
  exists v, eval_expr ge sp e m le (intuoffloat a) v /\ Val.lessdef y v.
Proof.
  intros. destruct x; simpl in H0; try discriminate.
  destruct (Float.intuoffloat f) as [n|]_eqn; simpl in H0; inv H0.
  exists (Vint n); split; auto. unfold intuoffloat.
  set (im := Int.repr Int.half_modulus).
  set (fm := Float.floatofintu im).
  assert (eval_expr ge sp e m (Vfloat f :: le) (Eletvar O) (Vfloat f)).
    constructor. auto. 
  econstructor. eauto.
  apply eval_Econdition with (v1 := Float.cmp Clt f fm).
  econstructor. constructor. eauto. constructor. EvalOp. simpl; eauto. constructor.
  simpl. auto.
  destruct (Float.cmp Clt f fm) as []_eqn.
  exploit Float.intuoffloat_intoffloat_1; eauto. intro EQ.
  EvalOp. simpl. rewrite EQ; auto.
  exploit Float.intuoffloat_intoffloat_2; eauto. intro EQ.
  set (t1 := Eop (Ofloatconst (Float.floatofintu Float.ox8000_0000)) Enil).
  set (t2 := subf (Eletvar 0) t1).
  set (t3 := intoffloat t2).
  exploit (eval_subf (Vfloat f :: le) (Eletvar 0) (Vfloat f) t1). 
    auto. unfold t1; EvalOp. simpl; eauto. 
  fold t2. intros [v2 [A2 B2]]. simpl in B2. inv B2. 
  exploit (eval_addimm Float.ox8000_0000 (Vfloat f :: le) t3).
    unfold t3. unfold intoffloat. EvalOp. simpl. rewrite EQ. simpl. eauto. 
  intros [v4 [A4 B4]]. simpl in B4. inv B4. 
  rewrite Int.sub_add_opp in A4. rewrite Int.add_assoc in A4. 
  rewrite (Int.add_commut (Int.neg Float.ox8000_0000)) in A4. 
  rewrite Int.add_neg_zero in A4. 
  rewrite Int.add_zero in A4.
  auto.
Qed.

Theorem eval_floatofint:
  forall le a x y,
  eval_expr ge sp e m le a x ->
  Val.floatofint x = Some y ->
  exists v, eval_expr ge sp e m le (floatofint a) v /\ Val.lessdef y v.
Proof.
  intros. destruct x; simpl in H0; inv H0.
  exists (Vfloat (Float.floatofint i)); split; auto.
  unfold floatofint.
  set (t1 := addimm Float.ox8000_0000 a).
  set (t2 := Eop Ofloatofwords (Eop (Ointconst Float.ox4330_0000) Enil ::: t1 ::: Enil)).
  set (t3 := Eop (Ofloatconst (Float.from_words Float.ox4330_0000 Float.ox8000_0000)) Enil).
  exploit (eval_addimm Float.ox8000_0000 le a). eauto. fold t1. 
  intros [v1 [A1 B1]]. simpl in B1. inv B1.
  exploit (eval_subf le t2). 
  unfold t2. EvalOp. constructor. EvalOp. simpl; eauto. constructor. eauto. constructor. 
  unfold eval_operation. eauto. 
  instantiate (2 := t3). unfold t3. EvalOp. simpl; eauto.
  intros [v2 [A2 B2]]. simpl in B2. inv B2. rewrite Float.floatofint_from_words. auto.
Qed.

Theorem eval_floatofintu:
  forall le a x y,
  eval_expr ge sp e m le a x ->
  Val.floatofintu x = Some y ->
  exists v, eval_expr ge sp e m le (floatofintu a) v /\ Val.lessdef y v.
Proof.
  intros. destruct x; simpl in H0; inv H0.
  exists (Vfloat (Float.floatofintu i)); split; auto.
  unfold floatofintu.
  set (t2 := Eop Ofloatofwords (Eop (Ointconst Float.ox4330_0000) Enil ::: a ::: Enil)).
  set (t3 := Eop (Ofloatconst (Float.from_words Float.ox4330_0000 Int.zero)) Enil).
  exploit (eval_subf le t2). 
  unfold t2. EvalOp. constructor. EvalOp. simpl; eauto. constructor. eauto. constructor. 
  unfold eval_operation. eauto. 
  instantiate (2 := t3). unfold t3. EvalOp. simpl; eauto.
  intros [v2 [A2 B2]]. simpl in B2. inv B2. rewrite Float.floatofintu_from_words. auto.
Qed.

Theorem eval_addressing:
  forall le chunk a v b ofs,
  eval_expr ge sp e m le a v ->
  v = Vptr b ofs ->
  match addressing chunk a with (mode, args) =>
    exists vl,
    eval_exprlist ge sp e m le args vl /\ 
    eval_addressing ge sp mode vl = Some v
  end.
Proof.
  intros until v. unfold addressing; case (addressing_match a); intros; InvEval.
  exists (@nil val). split. eauto with evalexpr. simpl. auto.
  exists (@nil val). split. eauto with evalexpr. simpl. auto.
  exists (v0 :: nil). split. eauto with evalexpr. simpl. congruence.
  exists (v1 :: nil). split. eauto with evalexpr. simpl. congruence.
  exists (v1 :: v0 :: nil). split. eauto with evalexpr. simpl. congruence.
  exists (v :: nil). split. eauto with evalexpr. subst v. simpl. 
  rewrite Int.add_zero. auto.
Qed.

Theorem eval_cond_of_expr:
  forall le a v b,
  eval_expr ge sp e m le a v ->
  Val.bool_of_val v b ->
  match cond_of_expr a with (cond, args) =>
    exists vl,
    eval_exprlist ge sp e m le args vl /\
    eval_condition cond vl m = Some b
  end.
Proof.
  intros until v. unfold cond_of_expr; case (cond_of_expr_match a); intros; InvEval.
  subst v. exists (v1 :: nil); split; auto with evalexpr.
  simpl. destruct b.
  generalize (Val.bool_of_true_val2 _ H0); clear H0; intro ISTRUE.
  destruct v1; simpl in ISTRUE; try contradiction. 
  rewrite Int.eq_false; auto.
  generalize (Val.bool_of_false_val2 _ H0); clear H0; intro ISFALSE.
  destruct v1; simpl in ISFALSE; try contradiction.
  rewrite ISFALSE. rewrite Int.eq_true; auto.
  exists (v :: nil); split; auto with evalexpr.
  simpl. inversion H0; simpl. rewrite Int.eq_false; auto. auto. auto. 
Qed.

End CMCONSTR.

