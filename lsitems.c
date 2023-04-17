#include <stdio.h>
#include <ctype.h>
#include <unistd.h>
#include <sys/stat.h>
#include "coverett.h"
#include "devices/inventory_operations.h"

int main(int argc, char* argv[])
{
    if (argc < 2){
        puts("LiSt Items");
        puts("Usage: lsitems <side>");
        return 0;
    }

    bus_t stdbus = openBus("/dev/hvc0");

    if(stdbus == NULL) {
        fputs("Failed to open bus.\n", stderr);
        return -1;
    }

    device_t dev = findDev(stdbus, "inventory_operations");
    if (!dev.exists){
        fputs("This program requires a Inventory Operations Module.\n", stderr);
        return -1;
    }

    result_t res = getItems(&dev, argv[1]);

    const cJSON *item = NULL;
    cJSON_ArrayForEach(item, res.retList) {
        if(cJSON_IsNull(item)) continue;
        
        char* id = strdup(cJSON_GetObjectItemCaseSensitive(item, "id")->valuestring);
        int count = cJSON_GetObjectItemCaseSensitive(item, "Count")->valueint;

        printf("(%ix %s)\n", count, id);
    }

    cJSON_Delete(res.retList);
}