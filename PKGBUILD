# Maintainer: Yaroslav Yushchenko <yaroslav.yushchenko1@gmail.com>
#
# Builds the latest commit from GitHub. For tagged releases, see
# packaging/arch/PKGBUILD or the pacman repository in the README.
pkgname=acer-predator-ph315-51-fan-control-git
pkgver=1.1.0.r0.g0000000
pkgrel=1
pkgdesc="Manual fan control (auto/full) for the Acer Predator PH315-51 via direct EC register writes"
arch=('any')
url="https://github.com/yaroslavyushchenko/fan-control"
license=('MIT')
depends=('python' 'systemd' 'kmod')
makedepends=('git')
provides=('acer-predator-ph315-51-fan-control')
conflicts=('acer-predator-ph315-51-fan-control')
install=fan-control.install
source=("$pkgname::git+$url.git")
sha256sums=('SKIP')

pkgver() {
	cd "$pkgname"
	git describe --long --tags 2>/dev/null | sed 's/^v//;s/-/.r/;s/-/./' \
		|| printf "r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

check() {
	cd "$pkgname"
	make test
}

package() {
	cd "$pkgname"
	make PREFIX=/usr DESTDIR="$pkgdir" VERSION="$pkgver" install
	install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
