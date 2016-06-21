import std.array;
import std.datetime;
import std.file;
import std.getopt;
import std.path;
import std.stdio;
import std.string;


import vayne.compiler;
import vayne.serializer;


const(string)[] compile(string fileName, string target, CompilerOptions options) {
	auto compiled = vayne.compiler.compile(fileName, options);

	auto byteCode = serialize(compiled);
	std.file.write(target, byteCode);

	return compiled.dependencies;
}


int main(string[] args) {
	version (linux) {
		import etc.linux.memoryerror;
		registerMemoryErrorHandler();
	}

	auto result = 0;
	auto time = false;
	auto verbose = false;
	auto depCacheGenOnly = false;
	string outputDir;
	string depCacheDir;

	CompilerOptions compileOptions;

	try {
		auto opts = getopt(args,
			"r|print-preparse",	"print preparser result", &compileOptions.preparsePrint,
			"a|print-ast",		"print ast", &compileOptions.astPrint,
			"i|print-instrs",	"print generated instructions", &compileOptions.instrPrint,
			"k|print-consts",	"print generated constant slots", &compileOptions.constPrint,
			"b|print-bytecode",	"print generated bytecode and instructions", &compileOptions.byteCodePrint,
			"t|time",			"display elapsed time", &time,
			"v|verbose",		"verbose output", &verbose,
			"c|compress",		"compress HTML in between template tags (disables accurate line numbers)", &compileOptions.compress,
			"o|output-dir",		"output directory", &outputDir,
			"d|dep-cache-dir",	"dependant-cache directory", &depCacheDir,
			"g|dep-gen-only",	"only generate dependant-cache, do not re-compile dependants", &depCacheGenOnly,
			"j|search",			"search path(s) to look for source files", &compileOptions.search,
			"e|default-ext", 	"default source file extension (defaults to .html)", &compileOptions.ext);

		if (opts.helpWanted || (args.length != 2)) {
			defaultGetoptPrinter("Usage: vayne [OPTIONS] file\n", opts.options);
			return 1;
		}
	} catch (Exception e) {
		writeln(e.msg);
		return 1;
	}

	if (compileOptions.compress)
		compileOptions.lineNumbers = false;

	if (!outputDir.empty) {
		if (!isAbsolute(outputDir))
			outputDir = absolutePath(outputDir);
	}

	auto fileName = args[1];
	if (verbose)
		writeln("compiling ", fileName, "...");

	auto timeStart = Clock.currTime;

	try {
		auto target = buildNormalizedPath(outputDir, fileName ~ ".vayne");

		if (!outputDir.empty) {
			try {
				mkdirRecurse(outputDir);
			} catch(Throwable) {
			}
		}

		auto deps = compile(fileName, target, compileOptions);

		if (!depCacheDir.empty) {
			immutable depsExtension = ".deps";

			auto depsFileName = buildNormalizedPath(depCacheDir, fileName ~ depsExtension);
			try {
				mkdirRecurse(depsFileName.dirName);
			} catch(Throwable) {
			}

			if (!depCacheGenOnly) {
				if (!isAbsolute(depCacheDir))
					depCacheDir = absolutePath(depCacheDir);

				string[] dependants;
				foreach (entry; dirEntries(depCacheDir, SpanMode.breadth)) {
					if (!entry.isDir) {
						if (entry.name.extension == depsExtension) {
							foreach (depName; File(entry.name).byLine) {
								if (depName == fileName)
									dependants ~= relativePath(entry.name[0..$ - depsExtension.length], depCacheDir);
							}
						}
					}
				}

				if (dependants.length) {
					foreach(dependant; dependants) {
						if (verbose)
							writeln("compiling dependant ", dependant, "...");

						compile(dependant, outputDir, compileOptions);
					}
				}
			}

			Appender!string appender;
			appender.reserve(2 * 1024);
			foreach (depName; deps) {
				appender.put(depName);
				appender.put("\n");
			}

			std.file.write(depsFileName, appender.data);
		}
	} catch (Exception error) {
		writeln("error: ", error.msg);
		result = 1;
	}

	auto timeEnd = Clock.currTime;
	if (time)
		writeln(format("elapsed: %.1fms", (timeEnd - timeStart).total!"usecs" * 0.001f));

	return result;
}
