# Maintainer: Yaroslav Yushchenko <yaroslav.yushchenko1@gmail.com>
pkgname=acer-predator-ph315-51-fan-control-git
pkgver=1.0.0.r0.g0000000
pkgrel=1
pkgdesc="Manual fan control (auto/full) for the Acer Predator PH315-51 via direct EC register writes"
arch=('any')
url="https://github.com/yaroslavyushchenko/acer-predator-ph315-51-fan-control"
license=('MIT')
depends=('python' 'systemd')
makedepends=('git')
provides=('acer-predator-ph315-51-fan-control')
conflicts=('acer-predator-ph315-51-fan-control')
install=acer-predator-ph315-51-fan-control.install
source=("$pkgname::git+$url.git")
sha256sums=('SKIP')

pkgver() {
	cd "$pkgname"
	git describe --long --tags 2>/dev/null | sed 's/^v//;s/-/.r/;s/-/./' \
		|| printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

package() {
	cd "$pkgname"
	make PREFIX=/usr DESTDIR="$pkgdir" install
	install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
