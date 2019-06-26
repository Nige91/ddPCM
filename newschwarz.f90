module newschwarz
use ddcosmo
implicit none
! preconditioner array
real*8, allocatable :: nlprec(:,:,:)
real*8, parameter :: p = 1.0d0

contains

subroutine nddcosmo(phi,psi,esolv)
  ! new main (inside the module for clarity) 
  implicit none
  real*8, intent(in) :: phi(ncav), psi(nylm,nsph), esolv
  real*8, allocatable :: x(:,:), rhs(:,:), scr(:,:)
  integer :: isph
  allocate(x(nylm,nsph),rhs(nylm,nsph),scr(ngrid,nsph))

  ! build the RHS 
  call wghpot(phi, scr)
  do isph = 1, nsph
    call intrhs(isph,scr(:,isph),rhs(:,isph)) 
  end do
  call prtsph('rhs of the ddCOSMO equation',nsph,0,rhs)
  deallocate(scr)

  ! assemble and store the preconditioner
  call build_nlprec()
  stop
  return
end subroutine nddcosmo 

subroutine nlx(n,x,y)
  ! perform new LX multiplication
  implicit none
  integer, intent(in) :: n
  real*8, intent(in) :: x(nylm,nsph)
  real*8, intent(inout) :: y(nylm,nsph)
  real*8, allocatable :: pot(:), basloc(:), dbasloc(:,:)
  real*8, allocatable :: vplm(:), vcos(:), vsin(:)
  integer :: isph, jsph, its, l1, m1, ind
  integer :: istatus

  allocate(pot(ngrid),vplm(nylm),basloc(nylm),dbasloc(3,nylm), &
    & vcos(lmax+1),vsin(lmax+1),stat=istatus)
  if (istatus.ne.0) then
    write(6,*) 'Allocation failed in nlx.'
    stop
  end if

  do isph = 1, nsph
    call calcnv(isph,pot,x,basloc,dbasloc,vplm,vcos,vsin)
    call intrhs(isph,pot,y(:,isph))
  end do

  deallocate(pot,basloc,dbasloc,vplm,vcos,vsin)
  return 
end subroutine nlx

subroutine calcnv(isph,pot,sigma,basloc,dbasloc,vplm,vcos,vsin)
  implicit none
  integer, intent(in) :: isph
  real*8, intent(in) :: sigma(nylm,nsph)
  real*8, intent(out) :: pot(ngrid)
  real*8, intent(inout) :: basloc(nylm), dbasloc(3,nylm), vplm(nylm), &
    & vcos(lmax + 1), vsin(lmax + 1)
  integer :: its, jsph, ij
  real*8 :: fac1, fac2, fac3, wij, vvij, tij
  real*8 :: vij(3), sij(3)

  pot = zero
  do its = 1, ngrid
    if (ui(its,isph).lt.one) then
      do ij = inl(isph),inl(isph+1)-1
        jsph = nl(ij)
        ! compute geometrical variables
        vij = csph(:,isph) + rsph(isph)*grid(:,its) - csph(:,jsph)
        vvij = sqrt(dot_product(vij,vij))
        tij = vvij/rsph(jsph)
        if (tij.lt.one) then
          sij = vij/vvij
          ! compute ddcosmo wij
          wij = fsw(tij,se,eta)
          if (fi(its,isph).gt.one) then
            wij = wij/fi(its,isph)
          end if 
          ! assemble the rhs contraction
        end if
      end do
    end if
  end do
end subroutine calcnv

subroutine apply_nlprec()
  ! apply preconditioner
end subroutine apply_nlprec

subroutine build_nlprec()
  ! build preconditioner
  implicit none
  integer :: isph, its, l1, m1, ind, lm
  real*8 :: fac1, fac2, fac3
  integer :: istatus
  real*8, allocatable :: nlprec_bk(:,:,:), res(:,:)
  integer, allocatable :: ipiv(:)
  real*8, allocatable :: work(:)

  ! initialize the preconditioner
  allocate(nlprec(nylm,nylm,nsph),stat=istatus)
  nlprec = zero

  ! debug for matrix inversion
  ! allocate(nlprec_bk(nylm,nylm,nsph),res(nylm,nylm))

  ! allocate stuff for lapack matrix inversion
  allocate(ipiv(nylm),work(nylm),stat=istatus)

  write(6,*) four, pi, p, two, one
  ! dense contribution 
  do isph = 1, nsph
    fac1 = four*pi/(p*rsph(isph))
    do its = 1, ngrid
      fac2 = fac1*w(its)*(one - ui(its,isph))
      !write(6,*) fac2, fac1, w(its), ui(its,isph)
      do l1 = 0, lmax
        ind = l1*l1 + l1 + 1
        do m1 = -l1, l1
          fac3 = fac2*basis(ind+m1,its)*dble(l1)/(two*dble(l1) + one)
          !write(6,*) fac3, fac2, basis(ind+m1,its), dble(l1)/(two*dble(l1)+one)
          do lm = 1, nylm
            nlprec(lm,ind + m1,isph) = nlprec(lm,ind + m1,isph) + &
              & fac3*basis(lm,its)
          end do 
        end do
      end do
    end do
  end do
  
  ! diagonal contribution
  do isph = 1, nsph
    do l1 = 0, lmax
      fac1 = four*pi/(two*dble(l1) + one)
      ind = l1*l1 + l1 + 1
      do m1 = -l1, l1
        nlprec(ind + m1,ind + m1,isph) = nlprec(ind + m1,ind + m1,isph) &
          & + fac1
      end do
    end do 
  end do

  write(8,*) '#', nylm, 1
  call printmatrix(8,nlprec(:,:,1),nylm,nylm)

  ! invert 
  nlprec_bk = nlprec
  do isph = 1, nsph
    call dgetrf(nylm,nylm,nlprec(:,:,isph),nylm,ipiv,istatus)
    if (istatus.ne.0) then
      write(6,*) 'LU failed with code', istatus
      stop
    end if
    call dgetri(nylm,nlprec(:,:,isph),nylm,ipiv,work,nylm,istatus)
    if (istatus.ne.0) then
      write(6,*) 'Inversion failed'
      stop
    end if
  end do

  ! debug
  ! do isph = 1, nsph
  !   call dgemm('n','n',nylm,nylm,nylm,one,nlprec(:,:,isph),nylm, &
  !     & nlprec_bk(:,:,isph),nylm,zero,res,nylm)
  ! end do

  deallocate(ipiv,work)
  return
end subroutine build_nlprec


subroutine printmatrix(iout,a,m,n)
  implicit none 
  integer :: i, j
  integer, intent(in) :: iout, m, n
  real*8, intent(in) :: a(m,n)
  do i = 1, m
    do j = 1, n
      write(iout,'(F10.5 $)') a(i,j)
    end do 
    write(iout,*)
  end do
  return
end subroutine printmatrix

end module newschwarz