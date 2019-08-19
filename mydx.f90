module mydx
    use ddcosmo
    use ddpcm_lib, only : dx, dodiag
    implicit none
    real*8  :: tobohr
    real*8, parameter :: toang = 0.52917721092d0, tokcal = 627.509469d0
    real*8, allocatable :: x(:), y(:), z(:), rvdw(:), charge(:)

contains
    subroutine init
        implicit none
        integer :: i, n
        dodiag = .false.
        open (unit=100,file='Input.txt',form='formatted',access='sequential')
        read(100,*) iprint      ! printing flag
        read(100,*) nproc       ! number of openmp threads
        read(100,*) lmax        ! max angular momentum of spherical harmonics basis
        read(100,*) ngrid       ! number of lebedev points
        read(100,*) iconv       ! 10^(-iconv) is the convergence threshold for the iterative solver
        read(100,*) igrad       ! whether to compute (1) or not (0) forces
        read(100,*) eps         ! dielectric constant of the solvent
        read(100,*) eta         ! regularization parameter
        read(100,*) n           ! number of atoms
        allocate (x(n), y(n), z(n), rvdw(n), charge(n))
        do i = 1, n
            read(100,*) charge(i), x(i), y(i), z(i), rvdw(i)
        end do
        tobohr = 1.0d0 / toang
        x    = x * tobohr
        y    = y * tobohr
        z    = z * tobohr
        rvdw = rvdw *tobohr
        close (100)
        call ddinit(n, x, y, z, rvdw)
        deallocate (x, y, z, rvdw, charge)
    end subroutine init

    subroutine fini
        implicit none
        call memfree
    end subroutine fini

    subroutine get_sizes(nbasis_, ngrid_, nsph_)
        integer, intent(out) :: nbasis_, ngrid_, nsph_
        nbasis_ = nbasis
        ngrid_ = ngrid
        nsph_ = nsph
    end subroutine get_sizes

    subroutine get_spheres(nsph, csph_, rsph_)
        integer, intent(in) :: nsph
        real*8, intent(out) :: csph_(3, nsph), rsph_(nsph)
        csph_ = csph
        rsph_ = rsph
    end subroutine get_spheres

    subroutine get_ngrid_ext(ngrid_ext)
        integer, intent(out) :: ngrid_ext
    end subroutine get_ngrid_ext

    subroutine get_grid(ngrid_ext, cgrid, grid_sph)
        integer, intent(out) :: ngrid_ext
        real*8, intent(out) :: cgrid(3, ngrid_ext)
    end subroutine get_grid

    subroutine ddpcm_dx(nbasis, nsph, x, y)
        implicit none
        integer, intent(in) :: nbasis, nsph
        real*8, intent(in) :: x(nbasis, nsph)
        real*8, intent(out) :: y(nbasis, nsph)
        call dx(nbasis*nsph, x, y)
    end subroutine ddpcm_dx

    subroutine kernel_point(src, src_r, dst, lmax, nbasis, mat)
        implicit none
        integer, intent(in) :: lmax, nbasis
        real*8, intent(in) :: src(3), dst(3)
        real*8, intent(in) :: src_r
        real*8, intent(out) :: mat(nbasis)
        integer :: i, l, ind, m
        real*8 :: v(3), vv, t, s(3), tt, f
        real*8 :: basloc(nbasis), vplm(nbasis), vcos(lmax+1), vsin(lmax+1)
        real*8 :: fourpi
        fourpi = four * pi
        v = dst - src
        vv = sqrt(dot_product(v, v))
        t = vv / src_r
        s = v / vv
        ! build the local basis
        call ylmbas(s, basloc, vplm, vcos, vsin)
        ! with all the required stuff, finally compute
        ! the "potential" at the point
        tt = one / t
        do l = 0, lmax
            ind = l*l + l + 1
            f = fourpi * dble(l) / (two*dble(l) + one) * tt
            do m = -l, l
                mat(ind+m) = f * basloc(ind+m)
            end do
            tt = tt / t
        end do
    end subroutine kernel_point

    subroutine kernel_point_ngrid(src_c, src_r, dst_c, dst_r, lmax, nbasis, &
            & ngrid, mat)
        implicit none
        integer, intent(in) :: lmax, nbasis, ngrid
        real*8, intent(in) :: src_c(3), dst_c(3)
        real*8, intent(in) :: src_r, dst_r
        real*8, intent(out) :: mat(ngrid, nbasis)
        integer :: i, l, ind, m
        real*8 :: v(3), vi(3), vvi, ti, si(3), tt, f
        real*8 :: basloc(nbasis), vplm(nbasis), vcos(lmax+1), vsin(lmax+1)
        real*8 :: fourpi
        fourpi = four * pi
        do i = 1, ngrid
            vi = dst_c + dst_r*grid(:, i)
            call kernel_point(src_c, src_r, vi, lmax, nbasis, mat(i, :))
        end do
    end subroutine kernel_point_ngrid

    subroutine kernel_ngrid(src_c, src_r, dst_c, dst_r, lmax, nbasis, ngrid, &
            & mat)
        implicit none
        integer, intent(in) :: lmax, nbasis, ngrid
        real*8, intent(in) :: src_c(3), dst_c(3)
        real*8, intent(in) :: src_r, dst_r
        real*8, intent(out) :: mat(ngrid, nbasis)
        integer :: i, l, ind, m
        real*8 :: v(3), vi(3), vvi, ti, si(3), tt, f
        real*8 :: basloc(nbasis), vplm(nbasis), vcos(lmax+1), vsin(lmax+1)
        real*8 :: fourpi
        fourpi = four * pi
        v = dst_c - src_c
        do i = 1, ngrid
            vi = v + dst_r*grid(:, i)
            vvi = sqrt(dot_product(vi, vi))
            ti = vvi / src_r
            si = vi / vvi
            ! build the local basis
            call ylmbas(si, basloc, vplm, vcos, vsin)
            ! with all the required stuff, finally compute
            ! the "potential" at the point
            tt = one / ti
            do l = 0, lmax
                ind = l*l + l + 1
                f = fourpi * dble(l) / (two*dble(l) + one) * tt
                do m = -l, l
                    mat(i, ind+m) = f * basloc(ind+m)
                end do
                tt = tt / ti
            end do
        end do
    end subroutine kernel_ngrid

    subroutine gen_mat_kernel(nbasis, ngrid, nsph, mat)
        implicit none
        integer, intent(in) :: nbasis, ngrid, nsph
        real*8, intent(out) :: mat(ngrid, nsph, nbasis, nsph)
        real*8, allocatable :: vts(:), vplm(:), basloc(:), vcos(:), vsin(:)
        real*8 :: c(3), vij(3), sij(3)
        real*8 :: vvij, tij, fourpi, tt, f, f1
        integer :: its, isph, jsph, l, m, ind, lm, istatus

        allocate(vts(ngrid), vplm(nbasis), basloc(nbasis), vcos(lmax+1), &
            & vsin(lmax+1), stat=istatus)
        if(istatus .ne. 0) then
            write(6,*) 'gen_mat: allocation failed !'
            stop
        end if
        fourpi = four * pi

        do isph = 1, nsph
            do jsph = 1, nsph
                if(isph .eq. jsph) then
                    mat(:, isph, :, jsph) = zero
                    cycle
                end if
                call kernel_ngrid(csph(:, jsph), rsph(jsph), csph(:, isph), &
                    & rsph(isph), lmax, nbasis, ngrid, mat(:, isph, :, jsph))
                do its = 1, ngrid
                    mat(its, isph, :, jsph) = ui(its, isph) * &
                        & mat(its, isph, :, jsph)
                end do
            end do
        end do
        deallocate(vts, vplm, basloc, vcos, vsin, stat=istatus)
        if(istatus .ne. 0) then
            write(6,*) 'gen_mat: deallocation failed !'
            stop
        end if
    end subroutine gen_mat_kernel

    subroutine gen_mat_ngrid(nbasis, ngrid, nsph, mat)
        implicit none
        integer, intent(in) :: nbasis, ngrid, nsph
        real*8, intent(out) :: mat(ngrid, nsph, nbasis, nsph)
        real*8, allocatable :: vts(:), vplm(:), basloc(:), vcos(:), vsin(:)
        real*8 :: c(3), vij(3), sij(3)
        real*8 :: vvij, tij, fourpi, tt, f, f1
        integer :: its, isph, jsph, l, m, ind, lm, istatus

        allocate(vts(ngrid), vplm(nbasis), basloc(nbasis), vcos(lmax+1), &
            & vsin(lmax+1), stat=istatus)
        if(istatus .ne. 0) then
            write(6,*) 'gen_mat: allocation failed !'
            stop
        end if
        fourpi = four * pi

        do isph = 1, nsph
            do jsph = 1, nsph
                if(isph .eq. jsph) then
                    mat(:, isph, :, jsph) = zero
                    cycle
                end if
                do its = 1, ngrid
                    !if(ui(its, isph) .eq. zero) then
                    !    mat(its, isph, :, jsph) = zero
                    !    cycle
                    !end if
                    ! build the geometrical variables
                    c = csph(:, isph) + rsph(isph)*grid(:, its)
                    vij = c - csph(:, jsph)
                    vvij = sqrt(dot_product(vij, vij))
                    tij = vvij / rsph(jsph)
                    sij = vij / vvij 
                    ! build the local basis
                    call ylmbas(sij, basloc, vplm, vcos, vsin)
                    ! with all the required stuff, finally compute
                    ! the "potential" at the point
                    tt = one / tij
                    do l = 0, lmax
                        ind = l*l + l + 1
                        f = fourpi * dble(l) / (two*dble(l) + one) * tt! * &
                            !& ui(its, isph)
                        do m = -l, l
                            mat(its, isph, ind+m, jsph) = f * basloc(ind+m)
                            ! write(*, *) its, isph, ind+m, jsph, mat(its, isph, ind+m, jsph)
                        end do
                        tt = tt / tij
                    end do
                end do
            end do
        end do
        deallocate(vts, vplm, basloc, vcos, vsin, stat=istatus)
        if(istatus .ne. 0) then
            write(6,*) 'gen_mat: deallocation failed !'
            stop
        end if
    end subroutine gen_mat_ngrid

    subroutine gen_mat(nbasis, nsph, mat)
        implicit none
        integer, intent(in) :: nbasis, nsph
        real*8, intent(out) :: mat(nbasis, nsph, nbasis, nsph)
        real*8, allocatable :: vts(:,:), vplm(:), basloc(:), vcos(:), vsin(:)
        real*8 :: c(3), vij(3), sij(3)
        real*8 :: vvij, tij, fourpi, tt, f, f1
        integer :: its, isph, jsph, l, m, ind, lm, istatus

        allocate(vts(ngrid, nbasis), vplm(nbasis), basloc(nbasis), &
            & vcos(lmax+1), vsin(lmax+1), stat=istatus)
        if(istatus .ne. 0) then
            write(6,*) 'gen_mat: allocation failed !'
            stop
        end if
        fourpi = four * pi

        do isph = 1, nsph
            do jsph = 1, nsph
                if(isph .eq. jsph) then
                    mat(:, isph, :, jsph) = zero
                    cycle
                end if
                do its = 1, ngrid
                    if(ui(its, isph) .eq. zero) then
                        vts(its, :) = zero
                        !mat(its, isph, :, jsph) = zero
                        cycle
                    end if
                    ! build the geometrical variables
                    c = csph(:, isph) + rsph(isph)*grid(:, its)
                    vij = c - csph(:, jsph)
                    vvij = sqrt(dot_product(vij, vij))
                    tij = vvij / rsph(jsph)
                    sij = vij / vvij 
                    ! build the local basis
                    call ylmbas(sij, basloc, vplm, vcos, vsin)
                    ! with all the required stuff, finally compute
                    ! the "potential" at the point
                    tt = one / tij
                    do l = 0, lmax
                        ind = l*l + l + 1
                        f = fourpi * dble(l) / (two*dble(l) + one) * tt * &
                            & ui(its, isph)
                        do m = -l, l
                            vts(its, ind+m) = f * basloc(ind+m)
                            !mat(its, isph, ind+m, jsph) = f * basloc(ind+m)
                            ! write(*, *) its, isph, ind+m, jsph, mat(its, isph, ind+m, jsph)
                        end do
                        tt = tt / tij
                    end do
                end do
                do ind = 1, nbasis
                    call intrhs(isph, vts(:, ind), mat(:, isph, ind, jsph))
                end do
            end do
        end do
        deallocate(vts, vplm, basloc, vcos, vsin, stat=istatus)
        if(istatus .ne. 0) then
            write(6,*) 'gen_mat: deallocation failed !'
            stop
        end if
    end subroutine gen_mat

    subroutine result_integrate(nbasis, ngrid, nsph, y, z)
        implicit none
        integer, intent(in) :: nbasis, ngrid, nsph
        real*8, intent(in) :: y(ngrid, nsph)
        real*8, intent(out) :: z(nbasis, nsph)
        integer :: isph
        z = zero
        do isph = 1, nsph
            call intrhs(isph, y(:, isph), z(:, isph))
        end do
    end subroutine result_integrate

    subroutine result_integrate_ui(nbasis, ngrid, nsph, y, z)
        implicit none
        integer, intent(in) :: nbasis, ngrid, nsph
        real*8, intent(in) :: y(ngrid, nsph)
        real*8, intent(out) :: z(nbasis, nsph)
        real*8 :: tmp(ngrid)
        integer :: isph
        z = zero
        do isph = 1, nsph
            tmp = y(:, isph) * ui(:, isph)
            call intrhs(isph, tmp, z(:, isph))
        end do
    end subroutine result_integrate_ui

end module mydx
