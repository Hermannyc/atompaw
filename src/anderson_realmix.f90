!******************************************************************************
!
! File : anderson_realmix.f90  -- (modified version of anderson_mixing.f90)
!   by : Alan Tackett
!   on : 07/19/99
!  for : density mixing (originally written for pwpaw code)
!
!  This module contains routines to implement the extended Anderson
!  mixing method as outlined in V. Eyert, J. Comp. Phys. 124,  271(1996).
!
!  The method is defined by eq's: 2.1, 8.2, 7.7
!
!******************************************************************************

MODULE anderson_realmix

  IMPLICIT NONE!!!!!!
  SAVE

  TYPE Anderson_Context  !** Anderson Mixing context
     REAL(8)    :: NewMix    !** Amount of new vectors to mix, ie beta in paper.
     INTEGER :: Nmax      !** Max number of vectors to keep 
     INTEGER :: N         !** Current number of vectors in list
     INTEGER :: Slot      !** New fill Slot
     INTEGER :: VecSize   !** Size of each vector
     INTEGER :: Err_Unit  !** Error unit
     REAL(8), POINTER :: Matrix(:,:)
     REAL(8), POINTER :: Gamma(:)  !** Gamma as defined in 7.6
     REAL(8), POINTER :: DF(:,:)   !** Delta F
     REAL(8), POINTER :: Fprev(:)
     REAL(8), POINTER :: DX(:,:)
     REAL(8), POINTER :: Xprev(:)

     ! temporary constants and arrays needed for each call to Anderson_Mix
     INTEGER, POINTER :: IPIV(:)
     REAL(8),  POINTER :: S(:)
     REAL(8),  POINTER :: RWork(:)
     REAL(8), POINTER :: U(:,:)
     REAL(8), POINTER :: VT(:,:)
     REAL(8), POINTER :: Work(:)
     REAL(8), POINTER :: DupMatrix(:,:)
     INTEGER          :: Lwork
     INTEGER          :: LRwork
     REAL(8)           :: ConditionNo
     REAL(8)           :: MachAccur
  END TYPE Anderson_Context

  !******************************************************************************
CONTAINS
  !******************************************************************************


  !******************************************************************************
  !
  ! Anderson_Mix - Performs the actual mixing of the input vector with the
  !                history and retuns the result.
  !
  !   AC - Anderson context
  !   X  - Current vector on input and new guess on output
  !   F  - F(X) - X. Nonlinear mixing of input vector
  !
  ! Modified to call SVD routines
  !******************************************************************************

  SUBROUTINE Anderson_Mix(AC, X, F)
    SAVE
    TYPE  (Anderson_Context), INTENT(INOUT) :: AC
    REAL(8),                  INTENT(INOUT) :: X(:)
    REAL(8),                  INTENT(IN)    :: F(:)

    INTEGER :: i, slot, currentdim , n ,j
    REAL(8) :: term
    REAL(8)  :: tmp

    !** First determine where to store the new correction vectors ***
    AC%slot = AC%slot + 1
    IF (AC%Slot>AC%Nmax) AC%Slot = 1

    IF ((AC%N < 0) .OR. (AC%Nmax == 0)) THEN  !** Simple mixing for 1st time ***
       AC%Xprev = X
       X = X + AC%NewMix*F
    ELSE
       slot = AC%Slot

       AC%DF(:,slot) = F - AC%Fprev   !** Make new DF vector
       AC%DX(:,slot) = X - AC%Xprev   !** Make new DX vector

       currentdim=MIN(AC%N+1,AC%Nmax)
       DO i=1, currentdim              !*** Add row/col to matrix
          term = DOT_PRODUCT(AC%DF(:,i), AC%DF(:,slot))
          AC%Matrix(i,slot) = term
          IF (i /= slot) AC%Matrix(slot,i) = (term)

          AC%Gamma(i) = DOT_PRODUCT(AC%DF(:,i), F)
       END DO


       AC%DupMatrix = AC%Matrix
       ! not needed (SVD) AC%DupMatrix(slot,slot) = (1+AC%w0) * AC%DupMatrix(slot,slot)
       !     Call ZHESV('L', Slot, 1, AC%DupMatrix(1,1), AC%Nmax, &
       !&         AC%IPIV(1), AC%Gamma(1), AC%Nmax, AC%Work(1), AC%LWork, i)

       !     Call ZGESV(Slot, 1, AC%DupMatrix(1,1), AC%Nmax, AC%IPIV(1), &
       !&         AC%Gamma(1), AC%Nmax, i)
       !    Call ZGESV(currentdim, 1, AC%DupMatrix(1,1), AC%Nmax, AC%IPIV(1), &
       !&        AC%Gamma(1), AC%Nmax, i)

       n = AC%Nmax;   j= currentdim
       CALL DGESDD('A',j,j,AC%DupMatrix(1,1),n,AC%S(1), &
&           AC%U(1,1),n,AC%VT(1,1),n,AC%Work(1),AC%Lwork, AC%IPIV(1),i)
       IF (i /= 0) THEN
          WRITE(AC%Err_Unit,*) 'Anderson_Mix: Error in DGESDD. Error=',i
          tmp = 0
          tmp = 1.d0/tmp
          STOP
       END IF

       WRITE(AC%Err_Unit,*) 'in Anderson_Mix -- completed SVD with values'
       WRITE(AC%Err_Unit,'(1p,5e15.7)') (AC%S(i),i=1,j)

       AC%Work(1:j) = AC%Gamma(1:j)
       AC%Gamma = 0
       tmp=MAX(ABS(AC%S(1))/AC%ConditionNo,AC%Machaccur)
       DO i=1,j
          IF (ABS(AC%S(i)).GT.tmp) THEN
             AC%Gamma(1:j)=AC%Gamma(1:j)+&
&                 (AC%VT(i,1:j))*DOT_PRODUCT(AC%U(1:j,i),AC%Work(1:j))/AC%S(i)
          ENDIF
       ENDDO


       AC%Xprev = X

       !*** Now calculate the new vector ***
       X = X + AC%NewMix*F

       !Do i=1, Min(AC%N+1,AC%Nmax)     !*** Add row/col to matrix
       DO i=1, currentdim               ! updated vector
          X = X - AC%Gamma(i)*(AC%DX(:,i) + AC%NewMix*AC%DF(:,i))
       END DO
    END IF


    AC%Fprev = F

    AC%N = AC%N + 1
    IF (AC%N > AC%Nmax) AC%N = AC%Nmax

    RETURN
  END SUBROUTINE Anderson_Mix

  !******************************************************************************
  !
  !  Anderson_ResetMix - Resets the mixing history to None
  !
  !     AC - Anderson context to reset
  !
  !******************************************************************************

  SUBROUTINE Anderson_ResetMix(AC)
    TYPE  (Anderson_Context), INTENT(INOUT) :: AC

    AC%N = -1
    AC%Slot = -1

    RETURN
  END SUBROUTINE Anderson_ResetMix

  !******************************************************************************
  !
  !  FreeAnderson - Frees all the data associated with the AC data structure
  !    
  !      AC -Pointer to the Anderson context to free
  !
  !******************************************************************************

  SUBROUTINE FreeAnderson(AC)
    TYPE (Anderson_Context), POINTER :: AC
    IF (ASSOCIATED(AC)) then
      IF (ASSOCIATED(AC%Matrix)) DEALLOCATE(AC%Matrix)
      IF (ASSOCIATED(AC%Gamma)) DEALLOCATE(AC%Gamma)
      IF (ASSOCIATED(AC%DF)) DEALLOCATE(AC%DF)
      IF (ASSOCIATED(AC%Fprev)) DEALLOCATE(AC%Fprev)
      IF (ASSOCIATED(AC%DX)) DEALLOCATE(AC%DX)
      IF (ASSOCIATED(AC%Xprev)) DEALLOCATE(AC%Xprev)
      IF (ASSOCIATED(AC%IPIV)) DEALLOCATE(AC%IPIV)
      IF (ASSOCIATED(AC%S)) DEALLOCATE(AC%S)
      IF (ASSOCIATED(AC%RWork)) DEALLOCATE(AC%RWork)
      IF (ASSOCIATED(AC%U)) DEALLOCATE(AC%U)
      IF (ASSOCIATED(AC%VT)) DEALLOCATE(AC%VT)
      IF (ASSOCIATED(AC%Work)) DEALLOCATE(AC%Work)
      IF (ASSOCIATED(AC%DupMatrix)) DEALLOCATE(AC%DupMatrix)
      DEALLOCATE(AC)
    END IF
  END SUBROUTINE FreeAnderson

  !******************************************************************************
  !
  !  InitAnderson - Initializes and Anderson_Context data structure for use
  !
  !   AC       - Anderson context created and returned
  !   Err_Unit - Output error unit
  !   Nmax     - Max number of vectors to keep
  !   VecSize  - Size of each vector
  !   NewMix   - Mixing factor
  !
  !******************************************************************************

  SUBROUTINE InitAnderson(AC, Err_Unit, Nmax, VecSize,  NewMix, CondNo)
    TYPE (Anderson_Context), POINTER     :: AC
    INTEGER,                 INTENT(IN)  :: Err_Unit
    INTEGER,                 INTENT(IN)  :: Nmax
    INTEGER,                 INTENT(IN)  :: VecSize
    REAL(8),                    INTENT(IN)  :: NewMix
    REAL(8),                    INTENT(IN)  :: CondNo

    INTEGER :: i
    REAL(8)    :: tmp , a1,a2,a3


    ALLOCATE(AC)   !** Allocate the pointer

    AC%Nmax = Nmax          !*** Store the contants
    AC%VecSize = VecSize
    AC%NewMix = NewMix
    AC%Err_Unit = Err_Unit

    AC%N = -1                !** Init the rest of the structure
    AC%Slot = -1
    !  AC%Lwork = 2*Nmax
    !  Allocate(AC%Gamma(Nmax), AC%Work(AC%Lwork), AC%Fprev(VecSize), &
    !&      AC%DF(VecSize, Nmax), AC%Matrix(Nmax, Nmax), AC%IPIV(Nmax), &
    !&      AC%DX(VecSize, Nmax), AC%Xprev(VecSize), &
    !&      AC%DupMatrix(Nmax, Nmax), STAT=i)

    ALLOCATE(AC%Xprev(VecSize), AC%Fprev(VecSize) , AC%DX(VecSize,Nmax), &
&        AC%DF(VecSize,Nmax), AC%Matrix(Nmax,Nmax) , AC%Gamma(Nmax), &
&        Stat=i)


    IF (i /= 0) THEN
       WRITE(Err_Unit,*) 'InitAnderson: Allocate Error! Error=',i
       WRITE(Err_Unit, *) 'InitAnderson: Nmax=',Nmax, ' * VecSize=',VecSize
       tmp = 0
       tmp = 1.d0/tmp
       STOP
    END IF

    AC%Lwork=5*Nmax*Nmax+10*Nmax
    AC%LRwork= 5*Nmax*Nmax+7*Nmax
    AC%ConditionNo= CondNo

    ! Calculate machine accuracy
    AC%Machaccur = 0
    a1 = 4.d0/3.d0
    DO WHILE (AC%Machaccur == 0.d0)
       a2 = a1 - 1.d0
       a3 = a2 + a2 + a2
       AC%Machaccur = ABS(a3 - 1.d0)
    ENDDO

    WRITE(Err_Unit,*) 'Machaccur = ', AC%Machaccur

    ALLOCATE(AC%DupMatrix(Nmax,Nmax), AC%U(Nmax, Nmax), AC%VT(Nmax,Nmax), &
&        AC%Work(AC%Lwork), AC%RWork(AC%LRWork), AC%IPIV(8*Nmax), &
&        AC%S(Nmax), STAT=i)

    AC%Matrix = 0

    RETURN
  END SUBROUTINE InitAnderson

END MODULE anderson_realmix
