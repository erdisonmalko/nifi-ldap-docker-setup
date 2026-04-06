## Getting Started: Importing, Configuring & Testing your NiFi Flow

Follow these steps to import the flow, configure required parameters, enable versioning, and validate the full Kafka → NiFi → CSV pipeline.

---

## 1. Locate the Flow Definition

The JSON definition for this flow is located in the repository at:

```bash
./templates/Kafka-to-CSV-Flow.json
```

---

## 2. Import to NiFi Canvas

1. Open the NiFi UI:

   ```
   https://localhost:8443/nifi
   ```

2. From the top components toolbar, drag the **Process Group** icon onto the canvas.

3. In the **Add Process Group** dialog:

   * Do not type a name yet
   * Click the **Upload icon** (next to the name field)
   * Select `Kafka-to-CSV-Flow.json` from your local machine

4. Once loaded:

   * Provide a name for your Process Group
   * Click **Add**

---

## 3. Create and Configure Parameter Context (Required)

This flow depends on parameters. Without this step, processors like `ConsumeKafka` and `PutFile` will fail.

### 3.1 Create Parameter Context

1. Go to:

   ```
   ☰ Menu → Parameter Contexts
   ```

2. Click **Create Parameter Context**

3. Name it:

   ```
   kafka-to-csv-params
   ```

---

### 3.2 Add Required Parameters

Add the following key-value pairs:

| Name                      | Value                               |
| ------------------------- | ----------------------------------- |
| `kafka.bootstrap.servers` | `kafka:9092`                        |
| `kafka.topic`             | `demo-topic`                        |
| `output.path`             | `/opt/nifi/nifi-current/output/csv` |

Save the context.

---

### 3.3 Assign Parameter Context to Process Group

1. Right-click your Process Group → **Edit**
2. Select:

   ```
   kafka-to-csv-params
   ```
3. Click **Apply**

---

## 4. Create a New Bucket in NiFi Registry

1. Open NiFi Registry UI:

   ```
   http://localhost:18080/nifi-registry
   ```

2. Click **Settings (wrench icon)**

3. Click **New Bucket**

4. Provide a name (e.g. `nifi-flows`) and click **Create**

---

## 5. Start Version Control

1. Go back to NiFi Canvas

2. Right-click your Process Group

3. Select:

   ```
   Version → Start version control
   ```

4. Configure:

   * Registry Client → your registry
   * Bucket → the one created above
   * Flow Name → e.g. `kafka-to-csv`

5. Click **Save**

---

## 6. Create Kafka Topic

Access Kafka container:

```bash
docker exec -it kafka bash
```

Create topic:

```bash
kafka-topics.sh \
  --create \
  --topic demo-topic \
  --bootstrap-server localhost:9092 \
  --partitions 1 \
  --replication-factor 1
```

Verify:

```bash
kafka-topics.sh --list --bootstrap-server localhost:9092
```

---

## 7. Produce Test Messages

Start producer:

```bash
kafka-console-producer.sh \
  --topic demo-topic \
  --bootstrap-server localhost:9092
```

Send sample JSON messages:

```json
{"id":1,"name":"Alice"}
{"id":2,"name":"Bob"}
{"id":3,"name":"Charlie"}
```

Exit with:

```
Ctrl + C
```

---

## 8. Start the NiFi Flow

Inside your Process Group:

Start all processors:

* `ConsumeKafka`
* `ValidateRecord`
* `UpdateAttribute`
* `PartitionRecord`
* `MergeRecord`
* `UpdateRecord`
* `ConvertRecord`
* `PutFile`

---

## 9. Validate Execution in NiFi

Check:

* `ConsumeKafka` → receiving data
* `MergeRecord` → batching records
* `PutFile` → successful FlowFiles

If issues:

* Check **bulletins (top-right)**
* Inspect **LogAttribute**
* Verify parameters are applied

---

## 10. Verify Output Files

Enter NiFi container:

```bash
docker exec -it nifi bash
```

Navigate:

```bash
cd /opt/nifi/nifi-current/output/csv
ls -R
```

Expected structure:

```bash
YYYY-MM-DD/HH/data_<date>_<hour>_<uuid>.csv
```

---

## 11. Inspect CSV Output

```bash
cat /opt/nifi/nifi-current/output/csv/*/*/*.csv
```

Expected:

```csv
id,name,ingestion_timestamp,source
1,Alice,1775497646900,kafka
2,Bob,1775497646901,kafka
3,Charlie,1775497646902,kafka
```

---

## Notes & Common Pitfalls

* **Empty filename in PutFile**
  → Ensure `filename` is set **after MergeRecord**

* **Directories not created**
  → Verify:

  ```
  Create Missing Directories = true
  ```

* **No Kafka data consumed**
  → Check:

  * Topic exists
  * `kafka.bootstrap.servers`
  * Consumer group configuration

* **Attributes missing after MergeRecord**
  → Set:

  ```
  Attribute Strategy = Keep All Unique Attributes
  ```

---

