---
title: libfprint replaced with libfprint-tod + Goodix driver
date: 2026-07-25
status: active
paths:
  - /usr/lib64/libfprint-2.so.2
---
# libfprint replaced with libfprint-tod + Goodix driver

The Goodix 27c6:550a fingerprint sensor (found in the Lenovo Legion Slim 5
14APH8 and other laptops) has no driver in upstream libfprint. The image
swaps `libfprint` for `libfprint-tod` (the touch-OEM-driver fork) plus the
Goodix TOD driver from COPR
`antiderivative/libfprint-tod-goodix-0.0.9`.

Confirmed working with fprintd enrollment and GDM fingerprint login. If GUI
enrollment reports a communication failure, CLI enrollment
(`fprintd-enroll -f right-index-finger`) can kick the device into a working
state, after which the GUI works as well.
