class Guest {
	static public function main():Int {
		var value = 1000;
		var total = 0;
		for (i in 0...50) total += 5;
		return value + total;
	}
}
